import 'package:child_track/app/home/model/trip_list_model.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
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

  void _onScroll() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Trips',
          style: AppTextStyles.headline5.copyWith(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        centerTitle: true,
      ),
      body: BlocBuilder<HomepageBloc, HomepageState>(
        bloc: _homepageBloc,
        builder: (context, state) {
          if (state is HomepageSuccess) {
            if (state.isLoadingTrips && state.trips.isEmpty) {
              return const TripsShimmer();
            }

            if (!state.isLoadingTrips && state.trips.isEmpty) {
              return const Center(child: Text("No trips found"));
            }

            return ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppSizes.paddingL),
              // Add +1 for loader if loading more
              itemCount: state.hasReachedMax
                  ? state.trips.length
                  : state.trips.length + 1,
              itemBuilder: (context, index) {
                if (index >= state.trips.length) {
                  return const TripsShimmer(itemCount: 1);
                }
                final trip = state.trips[index];
                return _SimpleTripCard(
                  trip: trip,
                  sourceIcon: _sourceIcon,
                  destinationIcon: _destinationIcon,
                );
              },
            );
          }
          return const TripsShimmer();
        },
      ),
    );
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

  IconData _getRideModeIcon(String rideMode) {
    switch (rideMode.toLowerCase()) {
      case 'walking':
        return Icons.directions_walk;
      case 'running':
        return Icons.directions_run;
      case 'cycling':
        return Icons.directions_bike;
      case 'stationary':
        return Icons.location_on;
      case 'vehicle':
        return Icons.directions_car;
      default:
        // Was falling through to directions_car — an unrecognized/missing
        // mode would show a car icon exactly like a real ride, which is the
        // same misleading-as-a-ride bug fixed elsewhere for this field.
        return Icons.help_outline;
    }
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
        markerId: const MarkerId('start'),
        position: LatLng(startPoint.lat, startPoint.lng),
        icon:
            startIconOverride ??
            sourceIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('end'),
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
      return const CameraPosition(target: LatLng(0, 0), zoom: 1);
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
      final yesterday = today.subtract(const Duration(days: 1));
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
    final dateLabel = _formatDateLabel(trip.startTime);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.spacingL),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Map Section
          SizedBox(
            height: 150,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppSizes.radiusL),
                topRight: Radius.circular(AppSizes.radiusL),
              ),
              child: trip.points.isNotEmpty
                  ? GoogleMap(
                      initialCameraPosition: _getInitialCameraPosition(),
                      liteModeEnabled: true,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: false,
                      polylines: _createPolylines(),
                      markers: _createMarkers(),
                      onMapCreated: (controller) {
                        if (trip.points.isNotEmpty) {
                          final bounds = _createBounds(
                            trip.points
                                .map((p) => LatLng(p.lat, p.lng))
                                .toList(),
                          );
                          controller.moveCamera(
                            CameraUpdate.newLatLngBounds(bounds, 20),
                          );
                        }
                      },
                    )
                  : Container(
                      color: Colors.grey[100],
                      child: const Center(child: Text('No path data')),
                    ),
            ),
          ),

          // Details Section
          Padding(
            padding: const EdgeInsets.all(AppSizes.paddingM),
            child: Column(
              children: [
                // Top Row: Time, Duration, Distance
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          children: [
                            if (dateLabel.isNotEmpty)
                              TextSpan(
                                text: '$dateLabel, ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            TextSpan(
                              // An ongoing trip has no real end time yet —
                              // points.last.ts (or json['end_time']) from
                              // whenever this list happened to be fetched
                              // is NOT one, and rendering it as a fixed
                              // range made a still-in-progress trip look
                              // like a short, already-finished one.
                              // Confirmed real incident: "8:46am - 8:49am,
                              // 0.4km" shown for a trip that was actually
                              // still running 30+ min and 8+ km later.
                              text: trip.isOngoing
                                  ? '${_formatTime(trip.startTime)} - now'
                                  : '${_formatTime(trip.startTime)} - ${_formatTime(trip.endTime)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (trip.isOngoing)
                              const TextSpan(
                                text: '   LIVE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.green,
                                ),
                              )
                            else
                              TextSpan(
                                text:
                                    '   ${_calculateDuration(trip.startTime, trip.endTime)}',
                                style: AppTextStyles.body2.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Icon(_getRideModeIcon(trip.rideMode)),
                    const SizedBox(width: AppSizes.spacingM),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${trip.distanceKm}km',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.spacingM),
                // Bottom Row: Timeline and View Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PlaceRenderer(
                            placeName: trip.fromPlace.isNotEmpty
                                ? trip.fromPlace
                                : 'Unknown Location',
                            point: trip.points.isNotEmpty
                                ? trip.points.first
                                : null,
                            iconColor: Colors.grey.shade400,
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 3.5),
                            height: 12,
                            width: 1,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          _PlaceRenderer(
                            placeName: trip.toPlace.isNotEmpty
                                ? trip.toPlace
                                : 'Unknown Location',
                            point: trip.points.isNotEmpty
                                ? trip.points.last
                                : null,
                            iconColor: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSizes.spacingM),
                    // Circular icon-only CTA (44px, #0069F9, arrow icon) —
                    // matches the Figma trip card's button shape/radius
                    // family instead of a labeled pill button.
                    GestureDetector(
                      onTap: () async {
                        if (trip.points.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("No detailed trip data available"),
                            ),
                          );
                          return;
                        }
                        injector<HomepageBloc>().add(
                          GetTripDetail(tripId: trip.tripId),
                        );
                        final tripSegment = TripSegment.fromTrip(trip);

                        // Use the resolved saved-place name (e.g. "Home") as
                        // the marker label/icon instead of a generic
                        // "START"/"END" pin, when the backend recognized one.
                        final startName =
                            trip.fromPlace.isNotEmpty &&
                                trip.fromPlace != 'Unknown Location'
                            ? _truncatePlaceLabel(trip.fromPlace)
                            : null;
                        final endName =
                            trip.toPlace.isNotEmpty &&
                                trip.toPlace != 'Unknown Location'
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
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0069F9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0070F0,
                              ).withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                // Removed redundant SizedBox and PlaceRenderers that were here
              ],
            ),
          ),
        ],
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
        return '(${hours}hrs ${minutes > 0 ? '$minutes min' : ''})'.trim();
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
  final Color iconColor;

  const _PlaceRenderer({
    required this.placeName,
    required this.point,
    required this.iconColor,
  });

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

    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: widget.iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: _isLoading
              ? SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSecondary,
                  ),
                )
              : Text(
                  displayText,
                  style: AppTextStyles.body2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}
