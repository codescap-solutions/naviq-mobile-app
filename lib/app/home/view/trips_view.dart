import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/app/home/view/widget/trip_summary_timeline.dart';
import 'package:child_track/app/home/model/trip_list_model.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/app/home/view/trip_detail_view.dart';
import 'package:child_track/app/home/model/last_trip_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:child_track/core/utils/map_marker_utils.dart';
import 'package:child_track/core/widgets/trips_shimmer.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/core/services/subscription_manager.dart';
import 'package:child_track/app/subscription/models/subscription_plan.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';

/// Trips List View - Shows all trips
class TripsView extends StatefulWidget {
  const TripsView({super.key});

  @override
  State<TripsView> createState() => _TripsViewState();
}

class _TripsViewState extends State<TripsView> {
  late HomepageBloc _homepageBloc;
  final ScrollController _scrollController = ScrollController();
  BitmapDescriptor? _sourceIcon;
  BitmapDescriptor? _destinationIcon;
  bool _historyLimitDialogShown = false;

  @override
  void initState() {
    super.initState();
    _homepageBloc = injector<HomepageBloc>();
    _homepageBloc.add(GetTrips(page: 1, pageSize: 10));
    _scrollController.addListener(_onScroll);
    _loadCustomMarkers();
  }

  Future<void> _loadCustomMarkers() async {
    try {
      final start = await MapMarkerUtils.getStartMarker();
      final end = await MapMarkerUtils.getEndMarker();
      if (mounted) {
        setState(() {
          _sourceIcon = start;
          _destinationIcon = end;
        });
      }
    } catch (e) {
      debugPrint('Error loading custom markers: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.addListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String? _shownTitle;

  void _onScroll() {
    final title = _titleFor(_homepageBloc.state);
    if (title != _shownTitle) {
      _shownTitle = title;
      setState(() {});
    }
    if (_isBottom) {
      final state = _homepageBloc.state;
      if (state is HomepageSuccess &&
          !state.isLoadingTrips &&
          !state.hasReachedMax) {
        if (_reachedTierHistoryCutoff(state.trips)) {
          _showHistoryLimitDialogOnce();
          return;
        }
        final nextPage = (state.tripsPage ?? 1) + 1;
        _homepageBloc.add(GetTrips(page: nextPage, pageSize: 10));
      }
    }
  }

  /// True once the oldest trip already loaded is at/past the current
  /// tier's history window — further pages would only contain trips the
  /// tier isn't allowed to browse, so pagination should stop there instead
  /// of relying on the backend to cut the list off.
  bool _reachedTierHistoryCutoff(List<Trip> trips) {
    // Premium's 30-day window is the max window any tier gets, and the
    // spec explicitly calls for no popup on Premium — don't cap it.
    if (SubscriptionManager.instance.currentTier == SubscriptionTier.premium) {
      return false;
    }
    if (trips.isEmpty) return false;
    final cutoff = DateTime.now().subtract(
      SubscriptionFeatureGate.tripHistoryWindow(),
    );
    final oldest = trips.last; // newest-first pages, so last = oldest loaded
    final oldestStart = DateTime.tryParse(oldest.startTime);
    if (oldestStart == null) return false;
    return oldestStart.isBefore(cutoff);
  }

  void _showHistoryLimitDialogOnce() {
    if (_historyLimitDialogShown || !mounted) return;
    _historyLimitDialogShown = true;
    final days = SubscriptionFeatureGate.tripHistoryWindow().inHours < 24
        ? '24 hours'
        : '${SubscriptionFeatureGate.tripHistoryWindow().inDays} days';
    UpgradeRestrictionDialog.show(
      context,
      title: 'Trip History Limit',
      message:
          'Your current plan shows the last $days of trip history. '
          'Upgrade to see older trips.',
      suggestedTier: SubscriptionFeatureGate.nextTier(),
    );
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  /// Height of one list item: 90 map + 185 details + 19 gap (Figma map card).
  double get _itemExtent => 294.w;

  /// App-bar title: the date ("Today" / "Yesterday" / "07 Oct 2026") of the
  /// card currently at the top of the list, "Trips" until trips are loaded.
  String _titleFor(HomepageState state) {
    if (state is! HomepageSuccess || state.trips.isEmpty) return 'Trips';
    final offset = _scrollController.hasClients ? _scrollController.offset : 0;
    final i = ((offset + 19.w) / _itemExtent).floor().clamp(
      0,
      state.trips.length - 1,
    );
    return TripSummarySheetBody.dateTitle(state.trips[i].startTime);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomepageBloc, HomepageState>(
      bloc: _homepageBloc,
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: figmaAppBar(context, title: _titleFor(state)),
          body: _buildBody(state),
        );
      },
    );
  }

  Widget _buildBody(HomepageState state) {
    if (state is HomepageSuccess) {
      if (state.isLoadingTrips && state.trips.isEmpty) return TripsShimmer();
      if (!state.isLoadingTrips && state.trips.isEmpty) {
        return Center(child: Text("No trips found"));
      }
      return ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        // Figma: 401px cards at x14, first card 19px under the header.
        padding: EdgeInsets.fromLTRB(14.w, 19.w, 14.w, 24.w),
        // +1 row for the "loading more" spinner, only while a page is
        // actually loading (the list used to end in an empty nested
        // scrollable that swallowed touches and blocked scrolling back up).
        itemCount: state.trips.length + (state.isLoadingTrips ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.trips.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 24.w),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _SimpleTripCard(
            trip: state.trips[index],
            sourceIcon: _sourceIcon,
            destinationIcon: _destinationIcon,
          );
        },
      );
    }
    return TripsShimmer();
  }
}

// Simplified Trip Card for List View (No Map Data)
class _SimpleTripCard extends StatelessWidget {
  final Trip trip;
  final BitmapDescriptor? sourceIcon;
  final BitmapDescriptor? destinationIcon;

  const _SimpleTripCard({
    required this.trip,
    this.sourceIcon,
    this.destinationIcon,
  });

  String _truncatePlaceLabel(String name) {
    const maxLen = 18;
    return name.length > maxLen ? '${name.substring(0, maxLen - 1)}…' : name;
  }

  Set<Polyline> _createPolylines() {
    if (trip.points.isEmpty) return {};

    final coordinates = trip.points
        .map((point) => LatLng(point.lat, point.lng))
        .toList();

    return {
      Polyline(
        polylineId: PolylineId('trip_${trip.tripId}'),
        points: coordinates,
        color: AppColors.tripPolyline,
        width: 3,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        patterns: trip.rideMode.toLowerCase() == 'walking'
            ? [PatternItem.dot, PatternItem.gap(10)]
            : [],
      ),
    };
  }

  Set<Marker> _createMarkers({
    BitmapDescriptor? startIconOverride,
    BitmapDescriptor? endIconOverride,
  }) {
    if (trip.points.isEmpty) return {};

    final startPoint = trip.points.first;
    final endPoint = trip.points.last;

    return {
      Marker(
        markerId: MarkerId('start'),
        position: LatLng(startPoint.lat, startPoint.lng),
        icon:
            startIconOverride ??
            sourceIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: MarkerId('end'),
        position: LatLng(endPoint.lat, endPoint.lng),
        icon:
            endIconOverride ??
            destinationIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }

  CameraPosition _getInitialCameraPosition() {
    if (trip.points.isEmpty) {
      return CameraPosition(target: LatLng(0, 0), zoom: 1);
    }
    final midIndex = trip.points.length ~/ 2;
    return CameraPosition(
      target: LatLng(trip.points[midIndex].lat, trip.points[midIndex].lng),
      zoom: 12,
    );
  }

  String _formatDateLabel(String timeStr) {
    if (timeStr.isEmpty) return '';
    try {
      DateTime dt;
      try {
        dt = DateTime.parse(timeStr).toLocal();
      } catch (_) {
        final inputFormat = DateFormat('dd-MM-yyyy HH:mm:ss');
        dt = inputFormat.parse(timeStr, true).toLocal();
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(Duration(days: 1));
      final dateToCheck = DateTime(dt.year, dt.month, dt.day);

      if (dateToCheck == today) {
        return 'Today';
      } else if (dateToCheck == yesterday) {
        return 'Yesterday';
      } else {
        return DateFormat('d MMM yyyy').format(dt);
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 19.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusL.w),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10.w,
            offset: Offset(0, 4.w),
          ),
        ],
      ),
      child: Column(
        children: [
          // Map Section
          SizedBox(
            height: 90.w,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppSizes.radiusL.w),
                topRight: Radius.circular(AppSizes.radiusL.w),
              ),
              child: trip.points.isNotEmpty
                  ? GoogleMap(
                      initialCameraPosition: _getInitialCameraPosition(),
                      liteModeEnabled: true,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: false,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      compassEnabled: false,
                      // Preview only: the card (and list) handle all touches.
                      scrollGesturesEnabled: false,
                      zoomGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      polylines: _createPolylines(),
                      markers: _createMarkers(),
                      onMapCreated: (controller) async {
                        // Wait for the 90px map to be laid out, otherwise the
                        // bounds are fitted to a zero-size view and the route
                        // ends up cut off / tiny.
                        await Future.delayed(Duration(milliseconds: 150));
                        final bounds = _createBounds(
                          trip.points.map((p) => LatLng(p.lat, p.lng)).toList(),
                        );
                        controller.moveCamera(
                          CameraUpdate.newLatLngBounds(bounds, 12),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[100],
                      child: Center(child: Text('No path data')),
                    ),
            ),
          ),

          // Details Section (Figma "map card": 185px under the 90px map)
          SizedBox(
            height: 185.w,
            child: Stack(
              children: [
                // Route: green start dot, 2px connector, red end dot.
                Positioned(
                  left: 34.w,
                  top: 33.5.w,
                  child: _dot(Color(0xFF34C759)),
                ),
                Positioned(
                  left: 37.w,
                  top: 45.5.w,
                  child: Container(
                    width: 2.w,
                    height: 23.w,
                    color: Color(0xFFDDE1EA),
                  ),
                ),
                Positioned(
                  left: 34.w,
                  top: 72.5.w,
                  child: _dot(Color(0xFFEF4444)),
                ),
                _routeRow(
                  top: 23,
                  placeName: trip.fromPlace.isNotEmpty
                      ? trip.fromPlace
                      : 'Unknown Location',
                  point: trip.points.isNotEmpty ? trip.points.first : null,
                  time: _timeLabel(trip.startTime),
                ),
                _routeRow(
                  top: 71,
                  placeName: trip.toPlace.isNotEmpty
                      ? trip.toPlace
                      : 'Unknown Location',
                  point: trip.points.isNotEmpty ? trip.points.last : null,
                  time: trip.isOngoing ? 'Now' : _timeLabel(trip.endTime),
                ),
                // Hairline between the route and the footer (Figma: y115).
                Positioned(
                  left: 0,
                  right: 0,
                  top: 115.w,
                  child: Container(height: 1, color: Color(0xFFEEF0F4)),
                ),
                // Footer: duration, distance and the 44px open button.
                Positioned(
                  left: 22.w,
                  top: 137.w,
                  child: Row(
                    children: [
                      if (trip.isOngoing)
                        Text(
                          'LIVE',
                          style: _metaStyle.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        _meta(
                          Icons.schedule_outlined,
                          _durationLabel(trip.startTime, trip.endTime),
                        ),
                      SizedBox(width: 16.w),
                      _meta(
                        Icons.location_on_outlined,
                        '${trip.distanceKm} km',
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 330.w,
                  top: 125.w,
                  child: GestureDetector(
                    onTap: () => _openDetail(context),
                    child: Container(
                      width: 44.w,
                      height: 44.w,
                      decoration: BoxDecoration(
                        color: Color(0xFF0069F9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF0070F0).withValues(alpha: 0.3),
                            blurRadius: 4.w,
                            offset: Offset(0, 2.w),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 16.w,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _metaStyle =>
      FigmaText.poppins(14, color: FigmaColors.body, lineHeight: 20);

  Widget _dot(Color color) => Container(
    width: 8.w,
    height: 8.w,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _meta(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 16.w, color: Color(0xFF0F1320)),
      SizedBox(width: 6.w),
      Text(text, style: _metaStyle),
    ],
  );

  /// One route line: place name at x54, time right-aligned (x ends at 369).
  Widget _routeRow({
    required double top,
    required String placeName,
    required TripPoint? point,
    required String time,
  }) {
    return Positioned(
      left: 54.w,
      right: 31.w,
      top: top.w,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _PlaceRenderer(placeName: placeName, point: point),
          ),
          SizedBox(width: 8.w),
          Padding(
            padding: EdgeInsets.only(top: 2.w),
            child: Text(
              time,
              style: FigmaText.poppins(
                12,
                color: FigmaColors.body,
                lineHeight: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "2:30 pm"; trips not from today get the date in front ("27 Sep, 7:54 pm").
  String _timeLabel(String timeStr) {
    final time = _formatTime(timeStr);
    final date = _formatDateLabel(timeStr);
    if (time.isEmpty || date.isEmpty || date == 'Today') return time;
    final short = date == 'Yesterday'
        ? date
        : date.replaceFirst(RegExp(r' \d{4}$'), '');
    return '$short, $time';
  }

  String _durationLabel(String startStr, String endStr) {
    final raw = _calculateDuration(startStr, endStr);
    return raw.length > 2 && raw.startsWith('(') && raw.endsWith(')')
        ? raw.substring(1, raw.length - 1)
        : raw;
  }

  Future<void> _openDetail(BuildContext context) async {
    if (trip.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No detailed trip data available")),
      );
      return;
    }
    injector<HomepageBloc>().add(GetTripDetail(tripId: trip.tripId));
    final tripSegment = TripSegment.fromTrip(trip);

    // Use the resolved saved-place name (e.g. "Home") as
    // the marker label/icon instead of a generic
    // "START"/"END" pin, when the backend recognized one.
    final startName =
        trip.fromPlace.isNotEmpty && trip.fromPlace != 'Unknown Location'
        ? _truncatePlaceLabel(trip.fromPlace)
        : null;
    final endName =
        trip.toPlace.isNotEmpty && trip.toPlace != 'Unknown Location'
        ? _truncatePlaceLabel(trip.toPlace)
        : null;

    final startIcon = startName != null
        ? await MapMarkerUtils.createCustomMarkerBitmap(
            startName,
            icon: startName.toLowerCase().contains('home')
                ? Icons.home
                : Icons.location_on,
            backgroundColor: AppColors.success,
            circleColor: AppColors.textSecondary,
          )
        : null;
    final endIcon = endName != null
        ? await MapMarkerUtils.createCustomMarkerBitmap(
            endName,
            icon: endName.toLowerCase().contains('home')
                ? Icons.home
                : Icons.location_on,
            backgroundColor: AppColors.error,
            circleColor: AppColors.textSecondary,
          )
        : null;

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TripDetailView(
          trip: tripSegment,
          markers: _createMarkers(
            startIconOverride: startIcon,
            endIconOverride: endIcon,
          ).toList(),
          polylines: _createPolylines().toList(),
        ),
      ),
    );
  }

  LatLngBounds _createBounds(List<LatLng> positions) {
    var south = positions.first.latitude;
    var north = positions.first.latitude;
    var west = positions.first.longitude;
    var east = positions.first.longitude;

    for (var i = 1; i < positions.length; i++) {
      var p = positions[i];
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }

    // Marker pins draw above their point, so leave headroom on the north edge.
    north += (north - south) * 0.3;
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  String _calculateDuration(String startStr, String endStr) {
    try {
      final start = DateTime.parse(startStr);
      final end = DateTime.parse(endStr);
      final duration = end.difference(start);
      if (duration.isNegative) return '(Invalid Trip Data)';
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);

      if (hours > 0) {
        return '($hours hr${hours > 1 ? 's' : ''}${minutes > 0 ? ' $minutes min' : ''})';
      } else {
        return '($minutes min)';
      }
    } catch (_) {
      return '';
    }
  }

  String _formatTime(String timeStr) {
    if (timeStr.isEmpty) return '';
    try {
      // First try ISO 8601 directly
      final dt = DateTime.parse(timeStr).toLocal();
      return DateFormat('h:mm a').format(dt).toLowerCase();
    } catch (_) {
      try {
        // Fallback for older model format: "dd-MM-yyyy HH:mm:ss"
        final inputFormat = DateFormat('dd-MM-yyyy HH:mm:ss');
        final dtParsed = inputFormat.parse(timeStr, true); // true = force UTC
        final dtLocal = dtParsed.toLocal();

        return DateFormat('h:mm a').format(dtLocal).toLowerCase();
      } catch (e) {
        return timeStr;
      }
    }
  }
}

class _PlaceRenderer extends StatefulWidget {
  final String placeName;
  final TripPoint? point;

  const _PlaceRenderer({required this.placeName, required this.point});

  @override
  State<_PlaceRenderer> createState() => _PlaceRendererState();
}

class _PlaceRendererState extends State<_PlaceRenderer> {
  String? _resolvedAddress;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (_shouldResolveAddress()) {
      _resolveAddress();
    }
  }

  bool _shouldResolveAddress() {
    return widget.placeName == "Unknown Location" && widget.point != null;
  }

  Future<void> _resolveAddress() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final placemarks = await placemarkFromCoordinates(
        widget.point!.lat,
        widget.point!.lng,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        setState(() {
          // Construct a simple address string
          _resolvedAddress = [
            place.street,
            place.subLocality,
            place.locality,
          ].where((e) => e != null && e.isNotEmpty).join(', ');

          if (_resolvedAddress!.isEmpty) {
            _resolvedAddress = "${place.name}";
          }
        });
      }
    } catch (e) {
      // debugPrint('Failed to resolve address: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _resolvedAddress ?? widget.placeName;

    if (_isLoading) {
      return SizedBox(
        height: 14.w,
        width: 14.w,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.textSecondary,
        ),
      );
    }
    return Text(
      displayText,
      maxLines: 1,
      style: FigmaText.poppins(
        16,
        weight: FontWeight.w600,
        color: Color(0xFF0F1320),
        lineHeight: 23,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
