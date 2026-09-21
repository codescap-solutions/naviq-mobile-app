import 'package:child_track/app/home/model/last_trip_model.dart';
import 'package:child_track/app/home/model/trip_detail_model.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/app/map/view/map_view.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/tracking/kalman_filter_service.dart';
import 'package:child_track/core/services/tracking/timeline_engine.dart';
import 'package:child_track/core/services/tracking/trip_playback_controller.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/app/subscription/widgets/subscription_popup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:child_track/core/widgets/resolved_place_label.dart';
import 'package:child_track/core/utils/responsive_font.dart';

/// Trip Detail View - Shows detailed trip with map and timeline
class TripDetailView extends StatefulWidget {
  const TripDetailView({
    super.key,
    required this.markers,
    required this.polylines,
    required this.trip,
  });
  final List<Marker> markers;
  final List<Polyline> polylines;
  final TripSegment trip;

  @override
  State<TripDetailView> createState() => _TripDetailViewState();
}

class _TripDetailViewState extends State<TripDetailView> {
  GoogleMapController? _mapController;
  late HomepageBloc _homepageBloc;
  late KalmanFilterService _kalmanService;
  TripPlaybackController? _playbackController;

  List<LatLng> _smoothedPoints = [];
  List<TimelineEvent> _timelineEvents = [];
  bool _detailPointsFitted = false; // prevents repeated camera fits

  // Playback values to rebuild UI
  LatLng? _currentPlaybackPosition;
  double _currentPlaybackSpeed = 1.0;
  bool _isPlaying = false;
  double _playbackProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _homepageBloc = injector<HomepageBloc>();
    _kalmanService = KalmanFilterService();

    // ── DEBUG: trace point counts entering TripDetailView ──────────
    debugPrint(
      '[TripDetailView] widget.trip.segmentId   = ${widget.trip.segmentId}',
    );
    debugPrint(
      '[TripDetailView] widget.trip.polylinePoints.length = ${widget.trip.polylinePoints.length}',
    );
    debugPrint(
      '[TripDetailView] widget.polylines.length = ${widget.polylines.length}',
    );
    // ───────────────────────────────────────────────────────────────

    // DIAGNOSTIC: Kalman bypassed — raw points to rule out filter coordinate collapse
    if (widget.trip.polylinePoints.isNotEmpty) {
      _smoothedPoints = List<LatLng>.from(widget.trip.polylinePoints);
    } else {
      _smoothedPoints = [];
    }

    debugPrint(
      '[TripDetailView] _smoothedPoints.length (Kalman OFF, raw) = ${_smoothedPoints.length}',
    );
    if (_smoothedPoints.isNotEmpty) {
      debugPrint('[TripDetailView] first point = ${_smoothedPoints.first}');
      debugPrint('[TripDetailView] last  point = ${_smoothedPoints.last}');
      final first10 = _smoothedPoints.take(10).toList();
      for (var i = 0; i < first10.length; i++) {
        debugPrint('[TripDetailView]   raw[$i] = ${first10[i]}');
      }
      final uniqueCount = _smoothedPoints
          .map((e) => '${e.latitude},${e.longitude}')
          .toSet()
          .length;
      debugPrint(
        '[TripDetailView] unique coords = $uniqueCount / ${_smoothedPoints.length}',
      );
    }

    // 2. Generate local timeline events as a fallback/offline view
    _generateLocalTimeline();

    // 3. Initialize Playback Controller if route exists
    if (_smoothedPoints.isNotEmpty) {
      _playbackController = TripPlaybackController(route: _smoothedPoints);
      _playbackController!.positionNotifier.addListener(
        _onPlaybackPositionChanged,
      );
      _playbackController!.progressNotifier.addListener(
        _onPlaybackProgressChanged,
      );
      _playbackController!.isPlayingNotifier.addListener(
        _onPlaybackPlayingChanged,
      );
      _playbackController!.speedNotifier.addListener(_onPlaybackSpeedChanged);
      _currentPlaybackPosition = _smoothedPoints.first;
    }
  }

  void _onPlaybackPositionChanged() {
    if (mounted) {
      setState(() {
        _currentPlaybackPosition = _playbackController?.currentPosition;
      });
      if (_currentPlaybackPosition != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_currentPlaybackPosition!),
        );
      }
    }
  }

  void _onPlaybackProgressChanged() {
    if (mounted) {
      setState(() {
        _playbackProgress = _playbackController?.progress ?? 0.0;
      });
    }
  }

  void _onPlaybackPlayingChanged() {
    if (mounted) {
      setState(() {
        _isPlaying = _playbackController?.isPlaying ?? false;
      });
    }
  }

  void _onPlaybackSpeedChanged() {
    if (mounted) {
      setState(() {
        _currentPlaybackSpeed = _playbackController?.speed ?? 1.0;
      });
    }
  }

  @override
  void dispose() {
    _playbackController?.positionNotifier.removeListener(
      _onPlaybackPositionChanged,
    );
    _playbackController?.progressNotifier.removeListener(
      _onPlaybackProgressChanged,
    );
    _playbackController?.isPlayingNotifier.removeListener(
      _onPlaybackPlayingChanged,
    );
    _playbackController?.speedNotifier.removeListener(_onPlaybackSpeedChanged);
    _playbackController?.dispose();
    super.dispose();
  }

  void _generateLocalTimeline() {
    try {
      final List<Map<String, dynamic>> rawPoints = [];
      final points = widget.trip.polylinePoints;
      final startTime =
          DateTime.tryParse(widget.trip.startTime) ?? DateTime.now();
      final endTime = DateTime.tryParse(widget.trip.endTime) ?? DateTime.now();
      final totalSeconds = endTime.difference(startTime).inSeconds;
      final stepSeconds = points.length > 1
          ? totalSeconds ~/ (points.length - 1)
          : 0;

      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final ts = startTime
            .add(Duration(seconds: i * stepSeconds))
            .toIso8601String();
        double speed = 0.0;
        if (i > 0) {
          final prev = points[i - 1];
          final dist = Geolocator.distanceBetween(
            prev.latitude,
            prev.longitude,
            p.latitude,
            p.longitude,
          );
          if (stepSeconds > 0) {
            speed = dist / stepSeconds; // m/s
          }
        }
        rawPoints.add({
          'lat': p.latitude,
          'lng': p.longitude,
          'speed': speed,
          'ts': ts,
        });
      }

      _timelineEvents = TimelineEngine.generate(
        points: rawPoints,
        initialRideMode: widget.trip.rideMode,
      );
    } catch (e) {
      // Fallback
      _timelineEvents = [
        TimelineEvent(
          type: TimelineEventType.tripStart,
          time: DateTime.tryParse(widget.trip.startTime) ?? DateTime.now(),
          label: 'Trip Started from ${widget.trip.startPlace}',
          lat: widget.trip.startLocation.latitude,
          lng: widget.trip.startLocation.longitude,
        ),
        TimelineEvent(
          type: TimelineEventType.arrived,
          time: DateTime.tryParse(widget.trip.endTime) ?? DateTime.now(),
          label: 'Arrived at ${widget.trip.endPlace}',
          lat: widget.trip.endLocation.latitude,
          lng: widget.trip.endLocation.longitude,
        ),
      ];
    }
  }

  int get _currentPlaybackIndex {
    if (_playbackController == null || _smoothedPoints.isEmpty) return 0;
    final pos = _playbackController!.currentPosition;
    final idx = _smoothedPoints.indexOf(pos);
    return idx >= 0 ? idx : 0;
  }

  double get _currentSpeedKmh {
    if (_smoothedPoints.isEmpty) return 0.0;
    final idx = _currentPlaybackIndex;
    if (idx == 0) return 0.0;
    final prev = _smoothedPoints[idx - 1];
    final curr = _smoothedPoints[idx];
    final dist = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );
    // Estimate speed based on a default time interval of 5 seconds
    final speedMps = dist / 5.0;
    final speedKmh = speedMps * 3.6;
    return speedKmh > 120 ? 0.0 : double.parse(speedKmh.toStringAsFixed(1));
  }

  String get _currentTimestamp {
    if (_smoothedPoints.isEmpty) return '';
    final idx = _currentPlaybackIndex;
    final start = DateTime.tryParse(widget.trip.startTime) ?? DateTime.now();
    final end = DateTime.tryParse(widget.trip.endTime) ?? DateTime.now();
    final totalSec = end.difference(start).inSeconds;
    final stepSec = _smoothedPoints.length > 1
        ? totalSec ~/ (_smoothedPoints.length - 1)
        : 0;
    final currentTs = start.add(Duration(seconds: idx * stepSec));
    return DateFormat('h:mm:ss a').format(currentTs).toLowerCase();
  }

  String _formatDateTime(String timeStr) {
    if (timeStr.isEmpty) return '';
    try {
      DateTime dt;
      try {
        dt = DateTime.parse(timeStr).toLocal();
      } catch (_) {
        final inputFormat = DateFormat('dd-MM-yyyy HH:mm:ss');
        dt = inputFormat.parse(timeStr, true).toLocal();
      }
      final outputFormat = DateFormat('dd-MM-yyyy hh:mma');
      return outputFormat.format(dt).toLowerCase();
    } catch (e) {
      return timeStr;
    }
  }

  void _fitBounds(List<LatLng> points) {
    if (_mapController == null || points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50.0, // padding
      ),
    );
  }

  /// Builds one Polyline per activity segment (walking/vehicle/etc.), each
  /// colored by its type, by bucketing the timestamped route into each
  /// segment's [startTime, endTime] window. Returns an empty list if there
  /// isn't enough timestamped data to do this reliably (caller falls back to
  /// a single-color line in that case).
  List<Polyline> _buildActivityColoredPolylines(
    List<RoutePoint> timedRoute,
    List<ActivitySegment> segments,
  ) {
    if (segments.isEmpty || timedRoute.length < 2) return [];

    final sortedPoints = List<RoutePoint>.from(timedRoute)
      ..sort((a, b) {
        if (a.timestamp == null || b.timestamp == null) return 0;
        return a.timestamp!.compareTo(b.timestamp!);
      });

    final result = <Polyline>[];
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final segStart = DateTime.tryParse(seg.startTime);
      final segEnd = DateTime.tryParse(seg.endTime);
      if (segStart == null || segEnd == null) continue;

      final segPoints = sortedPoints
          .where(
            (p) =>
                p.timestamp != null &&
                !p.timestamp!.isBefore(segStart) &&
                !p.timestamp!.isAfter(segEnd),
          )
          .map((p) => p.position)
          .toList();

      if (segPoints.length < 2) continue;

      result.add(
        Polyline(
          polylineId: PolylineId('segment_${i}_${seg.segmentId}'),
          points: segPoints,
          color: _colorForActivityType(seg.type),
          width: 7,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }
    return result;
  }

  Color _colorForActivityType(String type) {
    switch (type.toLowerCase()) {
      case 'walking':
        return const Color(0xFF22C55E); // green
      case 'running':
        return const Color(0xFFF59E0B); // amber
      case 'cycling':
        return const Color(0xFF8B5CF6); // purple
      case 'vehicle':
        return const Color(0xFF3B82F6); // blue
      case 'stationary':
        return const Color(0xFF94A3B8); // grey
      default:
        return AppColors.tripPolyline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (SubscriptionFeatureGate.showsHomePlaybackPromo()) {
      return _buildPlaybackPromoScreen(context);
    }
    return BlocProvider.value(
      value: _homepageBloc,
      child: BlocBuilder<HomepageBloc, HomepageState>(
        builder: (context, state) {
          List<TimelineEvent> displayEvents = _timelineEvents;
          double maxSpeed = widget.trip.maxSpeedKmph;
          double totalDistance = widget.trip.distanceKm;
          int durationMinutes = widget.trip.durationMinutes;

          if (state is HomepageSuccess &&
              state.selectedTripDetail != null &&
              state.selectedTripDetail!.tripId == widget.trip.segmentId) {
            final detail = state.selectedTripDetail!;
            maxSpeed = detail.maxSpeedKmph;
            totalDistance = detail.totalDistanceKm;
            try {
              durationMinutes = DateTime.parse(
                detail.endTime,
              ).difference(DateTime.parse(detail.startTime)).inMinutes;
            } catch (_) {}

            displayEvents = detail.events
                // LOCATION_RESUMED is deliberately not rendered as its own
                // node — the paired LOST_LOCATION card's duration already
                // conveys the full gap (matches the reference UI's single
                // grey "Lost location" node per gap, not two).
                .where((e) => e.eventType.toLowerCase() != 'location_resumed')
                .map((e) {
              // NOTE: these case strings match TimelineEvent.model.js's actual
              // eventType enum values (verified against the backend schema).
              // Several previously didn't (e.g. 'trip_start' vs the real
              // 'trip_started', 'walking'/'started_walking' vs the real
              // 'start_walking', 'left_place' vs the real 'left',
              // 'geofence_entered'/'geofence_exited' vs the real
              // 'geofence_enter'/'geofence_exit') — silently falling through
              // to the tripStart default for every one of those event types.
              TimelineEventType type = TimelineEventType.tripStart;
              switch (e.eventType.toLowerCase()) {
                case 'trip_started':
                  type = TimelineEventType.tripStart;
                  break;
                case 'start_walking':
                  type = TimelineEventType.startedWalking;
                  break;
                case 'start_running':
                  type = TimelineEventType.startedRunning;
                  break;
                case 'start_cycling':
                  type = TimelineEventType.startedCycling;
                  break;
                case 'start_vehicle':
                  type = TimelineEventType.startedVehicle;
                  break;
                case 'stopped':
                  type = TimelineEventType.stopped;
                  break;
                case 'arrived':
                  type = TimelineEventType.arrived;
                  break;
                case 'left':
                  type = TimelineEventType.leftPlace;
                  break;
                case 'geofence_enter':
                  type = TimelineEventType.geofenceEntered;
                  break;
                case 'geofence_exit':
                  type = TimelineEventType.geofenceExited;
                  break;
                case 'lost_location':
                  type = TimelineEventType.lostLocation;
                  break;
              }

              return TimelineEvent(
                type: type,
                time: DateTime.tryParse(e.time)?.toLocal() ?? DateTime.now(),
                // Short, fixed label for lost-location cards (matches the
                // reference UI's "Lost location" node) rather than the
                // backend's duration-embedding description, which would
                // otherwise duplicate the duration line rendered below it.
                label: type == TimelineEventType.lostLocation
                    ? 'Lost location'
                    : e.title,
                stopDuration: e.durationMinutes != null
                    ? Duration(minutes: e.durationMinutes!)
                    : null,
                speedKmh: e.maxSpeedKmph,
                distanceKm: e.distanceKm,
              );
            }).toList();
          }

          final markers = <Marker>{};
          if (widget.markers.isNotEmpty) {
            markers.addAll(widget.markers);
          }

          if (_currentPlaybackPosition != null) {
            markers.add(
              Marker(
                markerId: const MarkerId('playback_marker'),
                position: _currentPlaybackPosition!,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
                infoWindow: InfoWindow(
                  title: 'Current Playback',
                  snippet: '${_currentSpeedKmh} km/h • ${_currentTimestamp}',
                ),
              ),
            );
          }

          final polylines = <Polyline>{};

          // Determine the best available route points:
          // 1. Kalman-smoothed points from widget.trip (pre-populated)
          // 2. Route from fetched TripDetailResponse (arrives async)
          // 3. Polylines passed from parent screen
          final detailResponse =
              (state is HomepageSuccess && state.selectedTripDetail != null)
              ? state.selectedTripDetail!
              : null;

          // ── DEBUG: log ID comparison on every rebuild ────────────
          if (detailResponse != null) {
            debugPrint(
              '[TripDetailView] detail.tripId      = ${detailResponse.tripId}',
            );
            debugPrint(
              '[TripDetailView] widget.segmentId   = ${widget.trip.segmentId}',
            );
            debugPrint(
              '[TripDetailView] IDs match          = ${detailResponse.tripId == widget.trip.segmentId}',
            );
            debugPrint(
              '[TripDetailView] detail route pts   = ${detailResponse.polylinePoints.length}',
            );
          }
          debugPrint(
            '[TripDetailView] _smoothedPoints.length = ${_smoothedPoints.length}',
          );
          // ────────────────────────────────────────────────────────

          final detailPoints =
              (detailResponse != null &&
                  detailResponse.tripId == widget.trip.segmentId)
              ? detailResponse.polylinePoints
              : <LatLng>[];

          final activePoints = _smoothedPoints.isNotEmpty
              ? _smoothedPoints
              : detailPoints;

          debugPrint(
            '[TripDetailView] activePoints.length = ${activePoints.length}',
          );

          // Prefer one polyline per activity segment (walking/vehicle/etc.,
          // each its own color) using the timestamped route + segment time
          // windows from the fetched detail. Falls back to a single-color
          // line when that data isn't available yet (e.g. detail still
          // loading, or an older cached trip without per-point timestamps).
          final segmentedPolylines =
              (detailResponse != null &&
                  detailResponse.tripId == widget.trip.segmentId)
              ? _buildActivityColoredPolylines(
                  detailResponse.timedRoute,
                  detailResponse.segments,
                )
              : <Polyline>[];

          // segmentedPolylines being non-empty doesn't mean it's actually
          // USABLE — _buildActivityColoredPolylines buckets detailResponse's
          // (often much sparser than activePoints — confirmed real case:
          // 85 smoothed points vs. a 5-point detail fetch) timedRoute across
          // every activity segment's time window; with few points spread
          // across many segments, most segments get 0-1 points and get
          // skipped, but the couple that happen to land 2+ points still
          // produce a Polyline — just a tiny, near-invisible fragment
          // covering a fraction of the real route, while this branch being
          // non-empty means the full, accurate activePoints route below
          // never even gets considered. Require the segmented result to
          // actually cover a meaningful share of what we know is available
          // before trusting it over the plain full-route line.
          final segmentedPointCoverage = segmentedPolylines.fold<int>(
            0,
            (sum, p) => sum + p.points.length,
          );
          final segmentedIsUsable =
              activePoints.isEmpty ||
              segmentedPointCoverage >= activePoints.length * 0.5;

          if (segmentedPolylines.isNotEmpty && segmentedIsUsable) {
            polylines.addAll(segmentedPolylines);
          } else if (activePoints.isNotEmpty) {
            polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: activePoints,
                color: AppColors.tripPolyline,
                width: 6,
                geodesic: true,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            );
          } else if (widget.polylines.isNotEmpty) {
            polylines.addAll(widget.polylines);
          }

          if (polylines.isNotEmpty && !_detailPointsFitted) {
            _detailPointsFitted = true;
            final fitPoints = activePoints.isNotEmpty
                ? activePoints
                : polylines.expand((p) => p.points).toList();
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) _fitBounds(fitPoints);
            });
          }

          return Scaffold(
            backgroundColor: AppColors.backgroundColor,
            body: Stack(
              children: [
                // Map Section (Full screen)
                Positioned.fill(
                  child: _buildMapSection(
                    context,
                    markers.toList(),
                    polylines.toList(),
                  ),
                ),

                // Playback info overlay (top-mid)
                if (_isPlaying || _playbackProgress > 0.0)
                  Positioned(
                    top: 110,
                    left: 20,
                    right: 20,
                    child: Card(
                      color: AppColors.surfaceColor.withOpacity(0.95),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.speed,
                                color: AppColors.primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_currentSpeedKmh} km/h',
                                    style: AppTextStyles.subtitle1.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    _currentTimestamp,
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _playbackController?.pause();
                                _playbackController?.seekTo(0.0);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Draggable Bottom Sheet
                DraggableScrollableSheet(
                  initialChildSize: 0.4,
                  minChildSize: 0.25,
                  maxChildSize: 0.75,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppSizes.radiusXL),
                          topRight: Radius.circular(AppSizes.radiusXL),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                vertical: AppSizes.spacingM,
                              ),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.borderColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          // Playback Controls Panel (Always visible at the top of bottom sheet)
                          if (_playbackController != null)
                            _buildPlaybackControlPanel(),

                          const Divider(height: 1),

                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSizes.paddingL,
                                vertical: AppSizes.paddingM,
                              ),
                              children: [
                                _buildTripHeaderStats(
                                  totalDistance,
                                  durationMinutes,
                                  maxSpeed,
                                  detail: state is HomepageSuccess
                                      ? state.selectedTripDetail
                                      : null,
                                ),

                                // Activities Used: compact chip row derived from segments[].type
                                if (state is HomepageSuccess &&
                                    state.selectedTripDetail != null &&
                                    state
                                        .selectedTripDetail!
                                        .segments
                                        .isNotEmpty) ...[
                                  const SizedBox(height: AppSizes.spacingL),
                                  _buildActivitiesUsedSummary(
                                    state.selectedTripDetail!.segments,
                                  ),
                                ],

                                const SizedBox(height: AppSizes.spacingL),
                                const Divider(),
                                const SizedBox(height: AppSizes.spacingM),
                                Text(
                                  'Trip Timeline',
                                  style: AppTextStyles.subtitle1.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: AppSizes.spacingM),
                                if (state is HomepageSuccess &&
                                    state.isLoadingTripDetail)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24.0),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else
                                  // Unified, chronologically-ordered stepper:
                                  // activity segments (walk/ride, colored) +
                                  // lost-location gaps (grey) + notable place
                                  // events (arrived/left/geofence), matching
                                  // the reference UI's single continuous
                                  // timeline rather than two separate lists.
                                  ..._buildUnifiedTimeline(
                                    state is HomepageSuccess &&
                                            state.selectedTripDetail != null
                                        ? state.selectedTripDetail!.segments
                                        : const [],
                                    displayEvents,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Free-tier substitute for real route playback. No ad SDK is integrated
  /// in this app, so this is a static in-app upgrade promo rather than a
  /// real advertisement — see subscription restriction plan notes.
  Widget _buildPlaybackPromoScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Trip Playback',
          style: AppTextStyles.headline5.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF0066FF), Color(0xFF6F9EFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Full Route Playback is a Paid Feature',
                textAlign: TextAlign.center,
                style: AppTextStyles.headline5.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upgrade your plan to watch this trip\'s route play back on the map, step by step.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body2.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => SubscriptionPopup.show(
                    context,
                    SubscriptionFeatureGate.nextTier(),
                  ),
                  child: Text(
                    'Upgrade Now',
                    style: TextStyle(
                      fontSize: 14.5.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackControlPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                iconSize: 32,
                color: AppColors.primaryColor,
                icon: Icon(
                  _playbackController!.isAtEnd
                      ? Icons.replay
                      : (_isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled),
                ),
                onPressed: () {
                  if (_playbackController!.isAtEnd) {
                    _playbackController!.replay();
                  } else if (_isPlaying) {
                    _playbackController!.pause();
                  } else {
                    _playbackController!.play();
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    value: _playbackProgress,
                    onChanged: (val) {
                      _playbackController!.seekTo(val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<double>(
                value: _currentPlaybackSpeed,
                underline: const SizedBox(),
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryColor,
                ),
                items: TripPlaybackController.supportedSpeeds.map((s) {
                  return DropdownMenuItem<double>(
                    value: s,
                    child: Text('${s}x'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    _playbackController!.setSpeed(val);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// From/To row using the resolved-place-name fallback — this screen
  /// previously had no place-name display on its primary render path at
  /// all (the generated timeline's start event just says "Trip Started"
  /// with no location), and the one place startPlace/endPlace WERE
  /// referenced (the error-fallback timeline labels further up this file)
  /// showed the raw "Unknown Location" string with no rescue, unlike the
  /// trips list screen's already-working reverse-geocoding fallback.
  Widget _buildRouteSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResolvedPlaceLabel(
          placeName: widget.trip.startPlace.isNotEmpty
              ? widget.trip.startPlace
              : 'Unknown Location',
          lat: widget.trip.startLocation.latitude,
          lng: widget.trip.startLocation.longitude,
          iconColor: Colors.grey.shade400,
        ),
        Container(
          margin: const EdgeInsets.only(left: 3.5),
          height: 12,
          width: 1,
          color: AppColors.textSecondary.withValues(alpha: 0.3),
        ),
        ResolvedPlaceLabel(
          placeName: widget.trip.endPlace.isNotEmpty
              ? widget.trip.endPlace
              : 'Unknown Location',
          lat: widget.trip.endLocation.latitude,
          lng: widget.trip.endLocation.longitude,
          iconColor: AppColors.primaryColor,
        ),
      ],
    );
  }

  Widget _buildTripHeaderStats(
    double distanceKm,
    int durationMinutes,
    double maxSpeedKmph, {
    TripDetailResponse? detail,
  }) {
    final showSplit = detail?.hasEstimatedDistance == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRouteSummary(),
        const SizedBox(height: AppSizes.spacingM),
        if (detail?.hasDangerousDriving == true)
          _buildDangerousDrivingBanner(detail!),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatItem(
              icon: Icons.directions_run,
              value: '${distanceKm.toStringAsFixed(2)} km',
              label: 'Distance',
              // Confirmed + Estimated split (Part B) — shown as a subtext
              // rather than blended into the headline number, so it's always
              // visible, not hidden behind an extra tap, in a child-safety
              // context.
              subtitle: showSplit
                  ? '${detail!.distanceConfirmedKm.toStringAsFixed(1)} confirmed + '
                      '${detail.distanceEstimatedKm.toStringAsFixed(1)} est.'
                  : null,
            ),
            _buildStatItem(
              icon: Icons.timer,
              value: '${durationMinutes} min',
              label: 'Duration',
            ),
            _buildStatItem(
              icon: Icons.speed,
              value: '${maxSpeedKmph.toStringAsFixed(1)} km/h',
              label: 'Max Speed',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDangerousDrivingBanner(TripDetailResponse detail) {
    final eventLabels = detail.drivingEvents.map((e) => e.label).toSet();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSizes.spacingM),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dangerous driving',
                  style: AppTextStyles.subtitle2.copyWith(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (eventLabels.isNotEmpty)
                  Text(
                    eventLabels.join(' • '),
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.orange.shade800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    String? subtitle,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryColor, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.subtitle2.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10.0.sp,
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // Activities Used – compact horizontal chip row
  // ─────────────────────────────────────────────────────────
  Widget _buildActivitiesUsedSummary(List<ActivitySegment> segments) {
    // Extract unique types, preserving order of first occurrence
    final seen = <String>{};
    final types = <String>[];
    for (final seg in segments) {
      final t = seg.type.toLowerCase();
      if (seen.add(t)) types.add(t);
    }

    if (types.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activities Used',
          style: AppTextStyles.subtitle1.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSizes.spacingS),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: types.map((type) {
            final data = _activityData(type);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: (data['color'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: (data['color'] as Color).withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data['emoji'] as String,
                    style: TextStyle(fontSize: 16.0.sp),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    data['label'] as String,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: data['color'] as Color,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // Activity Breakdown – detailed card for each segment
  // ─────────────────────────────────────────────────────────
  /// Merges activity segments + notable timeline events into one
  /// chronologically-ordered list of stepper widgets. Segment-redundant
  /// event types (start_walking/start_vehicle/stopped/trip_start — segments
  /// already convey these more richly with distance+duration) are excluded;
  /// lost-location gaps and place events (arrived/left/geofence) are kept.
  List<Widget> _buildUnifiedTimeline(
    List<ActivitySegment> segments,
    List<TimelineEvent> events,
  ) {
    const redundantWithSegments = {
      TimelineEventType.tripStart,
      TimelineEventType.startedWalking,
      TimelineEventType.startedRunning,
      TimelineEventType.startedCycling,
      TimelineEventType.startedVehicle,
      TimelineEventType.stopped,
    };

    // A stop under this length is just GPS noise or a momentary pause (a red
    // light, checking a phone mid-walk) — not worth its own timeline entry.
    // Only genuinely meaningful pauses (lunch stop, waiting somewhere) show up.
    const minStationarySeconds = 5 * 60;

    final items = <(DateTime time, Widget Function(bool isLast) build)>[];

    for (final seg in segments) {
      final startTime = DateTime.tryParse(seg.startTime);
      if (startTime == null) continue;
      final isTrivialStop = seg.type.toLowerCase() == 'stationary' &&
          seg.durationSeconds < minStationarySeconds;
      if (isTrivialStop) continue;
      items.add((
        startTime,
        (isLast) => _buildSegmentStepperItem(seg, isLast: isLast),
      ));
    }

    for (final event in events) {
      if (redundantWithSegments.contains(event.type)) continue;
      items.add((
        event.time,
        (isLast) => _buildEnhancedTimelineItem(event, isLast: isLast),
      ));
    }

    items.sort((a, b) => a.$1.compareTo(b.$1));

    if (items.isEmpty) return const [];
    return List.generate(
      items.length,
      (i) => items[i].$2(i == items.length - 1),
    );
  }

  Widget _buildSegmentStepperItem(ActivitySegment seg, {bool isLast = false}) {
    final data = _activityData(seg.type.toLowerCase());
    final color = data['color'] as Color;
    final emoji = data['emoji'] as String;
    final label = data['label'] as String;

    final distanceKm = seg.distanceMeters / 1000.0;
    final durationMin = (seg.durationSeconds / 60.0).round();
    final startTime = DateTime.tryParse(seg.startTime)?.toLocal();
    final timeStr = startTime != null
        ? DateFormat('h:mm a').format(startTime).toLowerCase()
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spacingL),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(emoji, style: TextStyle(fontSize: 15.0.sp)),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: color.withOpacity(0.3)),
                  ),
              ],
            ),
            const SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.subtitle2.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    seg.type.toLowerCase() == 'stationary'
                        ? '$durationMin min'
                        : '${distanceKm.toStringAsFixed(1)} km  •  $durationMin min',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spacingS),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns display data for an activity type. Falls back gracefully for
  /// unknown types, keeping forward-compatibility.
  Map<String, dynamic> _activityData(String type) {
    switch (type) {
      case 'vehicle':
      case 'car':
        return {'emoji': '🚗', 'label': 'Vehicle', 'color': Colors.purple};
      case 'walking':
        return {'emoji': '🚶', 'label': 'Walking', 'color': Colors.green};
      case 'running':
        return {'emoji': '🏃', 'label': 'Running', 'color': Colors.teal};
      case 'cycling':
        return {'emoji': '🚴', 'label': 'Cycling', 'color': Colors.orange};
      case 'stationary':
      case 'stopped':
        return {'emoji': '⏸️', 'label': 'Paused', 'color': Colors.grey};
      default:
        return {
          'emoji': '📍',
          'label': _capitalize(type),
          'color': AppColors.primaryColor,
        };
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// "Duration: X min" for short gaps, "Duration: X h" for long ones —
  /// matches the reference UI ("1 min" vs "3 h") instead of always minutes
  /// (which would otherwise render a 3-hour gap as "Duration: 180 min").
  String _formatEventDuration(Duration d) {
    if (d.inMinutes < 60) return 'Duration: ${d.inMinutes} min';
    final hours = d.inMinutes / 60.0;
    final rounded = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(1);
    return 'Duration: $rounded h';
  }

  Widget _buildEnhancedTimelineItem(TimelineEvent event, {bool isLast = false}) {
    Color color = AppColors.primaryColor;
    IconData icon = Icons.directions_walk;

    switch (event.type) {
      case TimelineEventType.tripStart:
        color = Colors.blue;
        icon = Icons.play_arrow;
        break;
      case TimelineEventType.startedWalking:
        color = Colors.green;
        icon = Icons.directions_walk;
        break;
      case TimelineEventType.startedRunning:
        color = Colors.teal;
        icon = Icons.directions_run;
        break;
      case TimelineEventType.startedCycling:
        color = Colors.orange;
        icon = Icons.directions_bike;
        break;
      case TimelineEventType.startedVehicle:
        color = Colors.purple;
        icon = Icons.directions_car;
        break;
      case TimelineEventType.stopped:
        color = Colors.grey;
        icon = Icons.pause;
        break;
      case TimelineEventType.arrived:
        color = Colors.red;
        icon = Icons.place;
        break;
      case TimelineEventType.leftPlace:
        color = Colors.amber;
        icon = Icons.exit_to_app;
        break;
      case TimelineEventType.geofenceEntered:
        color = Colors.indigo;
        icon = Icons.notifications_active;
        break;
      case TimelineEventType.geofenceExited:
        color = Colors.blueGrey;
        icon = Icons.notifications_none;
        break;
      case TimelineEventType.lostLocation:
        color = Colors.grey;
        icon = Icons.error_outline;
        break;
    }

    final timeStr = DateFormat('h:mm a').format(event.time).toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spacingL),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: AppColors.borderColor),
                  ),
              ],
            ),
            const SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          event.label,
                          style: AppTextStyles.subtitle2.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        timeStr,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (event.stopDuration != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatEventDuration(event.stopDuration!),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (event.speedKmh != null && event.speedKmh! > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Max speed: ${event.speedKmh!.toStringAsFixed(1)} km/h',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (event.distanceKm != null && event.distanceKm! > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Distance: ${event.distanceKm!.toStringAsFixed(2)} km',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSizes.spacingS),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection(
    BuildContext context,
    List<Marker> markers,
    List<Polyline> polylines,
  ) {
    return Stack(
      children: [
        Positioned.fill(
          child: MapViewWidget(
            onMapCreated: (controller) {
              _mapController = controller;
              _fitBounds(
                _smoothedPoints.isNotEmpty
                    ? _smoothedPoints
                    : widget.trip.polylinePoints,
              );
            },
            interactive: true,
            width: double.infinity,
            maxZoom: 20,
            height: double.infinity,
            currentPosition: _smoothedPoints.isNotEmpty
                ? _smoothedPoints.first
                : (widget.markers.isNotEmpty
                      ? widget.markers.first.position
                      : const LatLng(0, 0)),
            markers: markers,
            useEagerGestures: true,
            polylines: polylines,
            isPolyLines: true,
          ),
        ),
        Positioned(
          top: 50,
          left: 20,
          child: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
        ),
        Positioned(
          top: 50,
          left: 120,
          right: 120,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingM,
              vertical: AppSizes.paddingS,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            child: const Text(
              'Trip Details',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
