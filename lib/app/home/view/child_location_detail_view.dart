import 'package:child_track/app/home/model/last_trip_model.dart';
import 'package:child_track/app/home/view/trips_view.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/app/map/view/map_view.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/home/model/cards_model.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:child_track/core/utils/map_marker_utils.dart';
import 'package:geocoding/geocoding.dart';
import 'package:child_track/core/widgets/child_location_detail_shimmer.dart';
import 'package:intl/intl.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class ChildLocationDetailView extends StatefulWidget {
  const ChildLocationDetailView({super.key});

  @override
  State<ChildLocationDetailView> createState() =>
      _ChildLocationDetailViewState();
}

// ... other imports ...

class _ChildLocationDetailViewState extends State<ChildLocationDetailView> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _sourceIcon;
  BitmapDescriptor? _destinationIcon;

  @override
  void initState() {
    super.initState();
    _loadCustomMarkers();

    final bloc = injector<HomepageBloc>();
    bloc.add(GetHomepageData());
    bloc.add(GetTrips(page: 1, pageSize: 10));
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

  void _fitBounds(TripSegment trip) {
    if (_mapController == null) return;

    // Safety check for empty points
    if (trip.polylinePoints.isEmpty &&
        trip.startLocation.latitude == 0 &&
        trip.endLocation.latitude == 0) {
      return;
    }

    double minLat = trip.startLocation.latitude;
    double maxLat = trip.startLocation.latitude;
    double minLng = trip.startLocation.longitude;
    double maxLng = trip.startLocation.longitude;

    // Check end location
    if (trip.endLocation.latitude < minLat) minLat = trip.endLocation.latitude;
    if (trip.endLocation.latitude > maxLat) maxLat = trip.endLocation.latitude;
    if (trip.endLocation.longitude < minLng) {
      minLng = trip.endLocation.longitude;
    }
    if (trip.endLocation.longitude > maxLng) {
      maxLng = trip.endLocation.longitude;
    }

    // Check polyline points
    for (var point in trip.polylinePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // If points are all same or invalid, add some buffer
    if (minLat == maxLat && minLng == maxLng) {
      minLat -= 0.01;
      maxLat += 0.01;
      minLng -= 0.01;
      maxLng += 0.01;
    }

    try {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          50.0, // padding
        ),
      );
    } catch (e) {
      debugPrint('Error fitting map bounds: $e');
    }
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

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      DateTime dt;
      try {
        dt = DateTime.parse(dateStr).toLocal();
      } catch (_) {
        final inputFormat = DateFormat('dd-MM-yyyy HH:mm:ss');
        dt = inputFormat.parse(dateStr, true).toLocal();
      }
      return DateFormat('h:mm a').format(dt).toLowerCase();
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: injector<HomepageBloc>(),
      child: Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceColor,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Kid Location Details', style: AppTextStyles.body1),
        ),
        body: BlocBuilder<HomepageBloc, HomepageState>(
          builder: (context, state) {
            if (state is HomepageSuccess) {
              TripSegment? trip;
              if (state.trips.isNotEmpty) {
                trip = TripSegment.fromTrip(state.trips.first);
              } else if (state.yesterdayTrips.isNotEmpty) {
                trip = state.yesterdayTrips.first;
              }

              if (trip == null) {
                if (state.isLoading || state.isLoadingTrips) {
                  return const ChildLocationDetailShimmer();
                }
                return const Center(child: Text('No trip data available'));
              }

              return SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              left: AppSizes.paddingM,
                              right: AppSizes.paddingM,
                              //bottom: AppSizes.paddingM,
                              top: AppSizes.paddingM,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppSizes.radiusXL,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusXL,
                                  ),
                                ),
                                // padding: const EdgeInsets.all(AppSizes.paddingM),
                                child: Stack(
                                  children: [
                                    MapViewWidget(
                                      onMapCreated: (controller) {
                                        _mapController = controller;
                                        // Use a post-frame callback or small delay to ensure map size is calculated
                                        // before fitting bounds, though map is usually ready.
                                        Future.delayed(
                                          const Duration(milliseconds: 300),
                                          () {
                                            if (mounted) _fitBounds(trip!);
                                          },
                                        );
                                      },
                                      interactive: true,
                                      isPolyLines: true,
                                      myLocationButtonEnabled: false,
                                      myLocationEnabled: false,

                                      width: double.infinity,
                                      height: double.infinity,

                                      markers: [
                                        Marker(
                                          markerId: MarkerId('start'),
                                          position: LatLng(
                                            trip.startLocation.latitude,
                                            trip.startLocation.longitude,
                                          ),
                                          icon:
                                              _sourceIcon ??
                                              BitmapDescriptor.defaultMarkerWithHue(
                                                BitmapDescriptor.hueGreen,
                                              ),
                                        ),
                                        Marker(
                                          markerId: MarkerId('end'),
                                          position: LatLng(
                                            trip.endLocation.latitude,
                                            trip.endLocation.longitude,
                                          ),
                                          icon:
                                              _destinationIcon ??
                                              BitmapDescriptor.defaultMarkerWithHue(
                                                BitmapDescriptor.hueRed,
                                              ),
                                        ),
                                      ],
                                      polylines: [
                                        Polyline(
                                          polylineId: PolylineId('route'),
                                          points: trip.polylinePoints,
                                          color: AppColors.tripPolyline,
                                          width: 4,
                                          patterns:
                                              trip.rideMode.toLowerCase() ==
                                                  'walking'
                                              ? [
                                                  PatternItem.dot,
                                                  PatternItem.gap(10),
                                                ]
                                              : [],
                                        ),
                                      ],
                                    ),
                                    // Zoom Controls
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: Column(
                                        children: [
                                          _buildZoomButton(
                                            icon: Icons.add,
                                            onPressed: () {
                                              _mapController?.animateCamera(
                                                CameraUpdate.zoomIn(),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          _buildZoomButton(
                                            icon: Icons.remove,
                                            onPressed: () {
                                              _mapController?.animateCamera(
                                                CameraUpdate.zoomOut(),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            bottom: 10,
                            right: 30,
                            left: 30,
                            child: _buildTripTodayCard(
                              context,
                              trip,
                              withMargin: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildChildLocationCardContent(context, trip, state.cards),
                  ],
                ),
              );
            }
            return const ChildLocationDetailShimmer();
          },
        ),
      ),
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: AppColors.textPrimary, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildTripTodayCard(
    BuildContext context,
    TripSegment trip, {
    bool withMargin = true,
  }) {
    return Container(
      height: 85,
      margin: withMargin
          ? const EdgeInsets.symmetric(horizontal: AppSizes.paddingL)
          : EdgeInsets.zero,
      padding: const EdgeInsets.all(AppSizes.paddingS),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatDateLabel(trip.startTime).isNotEmpty ? '${_formatDateLabel(trip.startTime)}, ' : ''}${_formatDate(trip.startTime)} - ${_formatDate(trip.endTime)} (${trip.durationMinutes}min)',
                    style: AppTextStyles.overline.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // const SizedBox(height: AppSizes.spacingXS),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.paddingXS,
                          vertical: AppSizes.paddingXS,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundColor,
                          borderRadius: BorderRadius.circular(AppSizes.radiusS),
                        ),
                        child: Text(
                          '${trip.eventsCount} Events',
                          style: AppTextStyles.caption,
                        ),
                      ),
                      const SizedBox(width: AppSizes.spacingS),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.paddingS,
                          vertical: AppSizes.paddingXS,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppSizes.radiusS),
                        ),
                        child: Text(
                          _formatDate(trip.endTime),
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSizes.spacingS),
          CommonButton(
            padding: EdgeInsets.zero,
            width: 80,
            text: 'View all',
            fontSize: 12.0.sp,
            textColor: AppColors.surfaceColor,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TripsView()),
            ),
            height: 30,
          ),
        ],
      ),
    );
  }

  // First View: Child Location Info Card Content
  Widget _buildChildLocationCardContent(
    BuildContext context,
    TripSegment trip,
    Cards? cards,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.paddingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Second View: Trip Today Card
              //  _buildTripTodayCard(context),

              // Activity Today Card
              _buildActivityTodayCard(context, trip),
              const SizedBox(height: AppSizes.spacingM),

              // // ScreentimeCard
              // if (cards?.screentimeYesterday != null)
              //   _buildScreentimeCard(context, cards!.screentimeYesterday),
              // const SizedBox(height: AppSizes.spacingM),

              // // Infinite Real-Time Tracking Card
              // _buildInfiniteTrackingCard(),
              const SizedBox(height: AppSizes.spacingXL),
            ],
          ),
        ],
      ),
    );
  }

  // Activity Today Card
  Widget _buildActivityTodayCard(BuildContext context, TripSegment trip) {
    return Container(
      // margin: const EdgeInsets.all(AppSizes.paddingM),
      padding: const EdgeInsets.all(AppSizes.paddingM),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${trip.type.toUpperCase()} - ${_formatDateLabel(trip.startTime).isNotEmpty ? '${_formatDateLabel(trip.startTime)}, ' : ''}${_formatDate(trip.startTime)} - ${_formatDate(trip.endTime)}',
            style: AppTextStyles.headline6.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSizes.spacingM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Activity metrics
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildActivityMetric(
                            '${trip.distanceKm} km',
                            'Distance',
                          ),
                        ),
                        Expanded(
                          child: _buildActivityMetric(
                            '${trip.durationMinutes} min',
                            'Duration',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.spacingS),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildActivityMetric(
                            trip.endPlace.isNotEmpty
                                ? trip.endPlace
                                : trip.startPlace,
                            'Route',
                            isRoute: true,
                          ),
                        ),
                        Expanded(
                          child: _buildActivityMetric(
                            '${trip.maxSpeedKmph} km/h',
                            'Max Speed',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Progress indicator
              // Progress indicator
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: CircularProgressIndicator(
                            value: trip.progress / 100,
                            strokeWidth: 8,
                            backgroundColor: AppColors.borderColor,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primaryColor,
                            ),
                          ),
                        ),
                        Text(
                          '${trip.progress.toDouble().toStringAsFixed(1)}%',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor,
                            fontSize: 11.0.sp,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSizes.spacingS),
                    Expanded(
                      child: Text(
                        'more distance walked than last day',
                        maxLines: 3,
                        textAlign: TextAlign.start,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spacingM),
          Divider(color: AppColors.borderColor, thickness: 1),
          const SizedBox(height: AppSizes.spacingXS),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Track your child\'s weekly progress\nand get personalized growth tips!',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.spacingS),
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TripsView()),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'View all',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Activity Metric Widget
  Widget _buildActivityMetric(
    String value,
    String label, {
    bool isRoute = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTextStyles.subtitle2.copyWith(
            color: AppColors.primaryColor,
            fontWeight: FontWeight.w500,
          ),
          maxLines: isRoute ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2), // Fixed width to height for Column
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // // Screentime Card
  // Widget _buildScreentimeCard(BuildContext context, ScreenTimeCard card) {
  //   final double hours = card.totalSeconds / 3600;
  //   String timeText;
  //   if (hours >= 1) {
  //     timeText = '${hours.toStringAsFixed(1)}hrs';
  //   } else {
  //     final double minutes = card.totalSeconds / 60;
  //     if (card.totalSeconds > 0 && minutes < 1) {
  //       timeText = '< 1 min';
  //     } else {
  //       timeText = '${minutes.toStringAsFixed(0)}min';
  //     }
  //   }

  //   return Container(
  //     // margin: const EdgeInsets.symmetric(horizontal: AppSizes.paddingL),
  //     padding: const EdgeInsets.all(AppSizes.paddingM),
  //     decoration: BoxDecoration(
  //       color: AppColors.primaryColor.withValues(alpha: 0.1),
  //       borderRadius: BorderRadius.circular(AppSizes.radiusL),
  //     ),
  //     child: Row(
  //       children: [
  //         Container(
  //           width: 48,
  //           height: 48,
  //           decoration: BoxDecoration(
  //             color: AppColors.surfaceColor,
  //             borderRadius: BorderRadius.circular(AppSizes.radiusM),
  //           ),
  //           child: const Icon(
  //             Icons.grid_view,
  //             color: AppColors.primaryColor,
  //             size: 24,
  //           ),
  //         ),
  //         const SizedBox(width: AppSizes.spacingXS),
  //         Expanded(
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Text(
  //                 '$timeText of screentime',
  //                 style: AppTextStyles.subtitle1.copyWith(
  //                   fontWeight: FontWeight.bold,
  //                 ),
  //               ),
  //               const SizedBox(width: 2),
  //               Row(
  //                 children: [
  //                   // App icons placeholder
  //                   Container(
  //                     width: 15,
  //                     height: 15,
  //                     decoration: BoxDecoration(
  //                       color: AppColors.success,
  //                       borderRadius: BorderRadius.circular(AppSizes.radiusS),
  //                     ),
  //                   ),
  //                   const SizedBox(width: 2),
  //                   Container(
  //                     width: 15,
  //                     height: 15,
  //                     decoration: BoxDecoration(
  //                       color: AppColors.error,
  //                       borderRadius: BorderRadius.circular(AppSizes.radiusS),
  //                     ),
  //                   ),
  //                   const SizedBox(width: 2),
  //                   Container(
  //                     width: 15,
  //                     height: 15,
  //                     decoration: BoxDecoration(
  //                       color: AppColors.warning,
  //                       borderRadius: BorderRadius.circular(AppSizes.radiusS),
  //                     ),
  //                   ),
  //                   const SizedBox(width: 2),
  //                   Container(
  //                     width: 15,
  //                     height: 15,
  //                     decoration: BoxDecoration(
  //                       color: AppColors.info,
  //                       borderRadius: BorderRadius.circular(AppSizes.radiusS),
  //                     ),
  //                   ),
  //                   const SizedBox(width: AppSizes.spacingXS),
  //                   Text(
  //                     'and more yesterday',
  //                     style: AppTextStyles.caption.copyWith(
  //                       color: AppColors.textSecondary,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ],
  //           ),
  //         ),
  //         CommonButton(
  //           padding: EdgeInsets.zero,
  //           width: 70,
  //           text: 'View all',
  //           fontSize: 12,
  //           textColor: AppColors.surfaceColor,
  //           onPressed: () => Navigator.push(
  //             context,
  //             MaterialPageRoute(builder: (_) => const TripsView()),
  //           ),
  //           height: 26,
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // Infinite Real-Time Tracking Card (Bottom)
  //   Widget _buildInfiniteTrackingCard() {
  //     return Container(
  //       // margin: const EdgeInsets.all(AppSizes.paddingL),
  //       padding: const EdgeInsets.all(AppSizes.paddingL),
  //       decoration: BoxDecoration(
  //         color: AppColors.primaryColor.withValues(alpha: 0.1),
  //         borderRadius: BorderRadius.circular(AppSizes.radiusL),
  //       ),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(
  //             'INFINITE REAL-TIME TRACKING',
  //             style: AppTextStyles.subtitle1.copyWith(
  //               fontWeight: FontWeight.bold,
  //               color: AppColors.primaryColor,
  //             ),
  //           ),
  //           const SizedBox(height: AppSizes.spacingM),
  //           Row(
  //             children: [
  //               Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: List.generate(
  //                     4,
  //                     (index) => Padding(
  //                       padding: const EdgeInsets.only(
  //                         bottom: AppSizes.spacingXS,
  //                       ),
  //                       child: Row(
  //                         children: [
  //                           Icon(
  //                             Icons.check_circle,
  //                             size: 16,
  //                             color: AppColors.primaryColor,
  //                           ),
  //                           const SizedBox(width: AppSizes.spacingXS),
  //                           Text(
  //                             'Unlimited Updated, just for you',
  //                             style: AppTextStyles.caption,
  //                           ),
  //                         ],
  //                       ),
  //                     ),
  //                   ),
  //                 ),
  //               ),
  //               // Gift box placeholder
  //               Container(
  //                 width: 60,
  //                 height: 60,
  //                 decoration: BoxDecoration(
  //                   color: AppColors.surfaceColor,
  //                   borderRadius: BorderRadius.circular(AppSizes.radiusM),
  //                 ),
  //                 child: const Icon(
  //                   Icons.card_giftcard,
  //                   color: AppColors.primaryColor,
  //                   size: 32,
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ],
  //       ),
  //     );
  //   }
  // }
}

class _RouteRenderer extends StatefulWidget {
  final String startPlace;
  final String endPlace;
  final LatLng startLocation;
  final LatLng endLocation;

  const _RouteRenderer({
    required this.startPlace,
    required this.endPlace,
    required this.startLocation,
    required this.endLocation,
  });

  @override
  State<_RouteRenderer> createState() => _RouteRendererState();
}

class _RouteRendererState extends State<_RouteRenderer> {
  String? _resolvedStart;
  String? _resolvedEnd;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (_shouldResolve()) {
      _resolveAddresses();
    }
  }

  bool _shouldResolve() {
    return widget.startPlace == "Unknown Location" ||
        widget.endPlace == "Unknown Location";
  }

  Future<String?> _resolveSingle(LatLng pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = [
          place.street,
          place.subLocality,
          place.locality,
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        return address.isNotEmpty ? address : place.name;
      }
    } catch (e) {
      debugPrint('Error resolving address: $e');
    }
    return null;
  }

  Future<void> _resolveAddresses() async {
    if (mounted) setState(() => _isLoading = true);

    String? startAddr;
    String? endAddr;

    if (widget.startPlace == "Unknown Location") {
      startAddr = await _resolveSingle(widget.startLocation);
    }

    if (widget.endPlace == "Unknown Location") {
      endAddr = await _resolveSingle(widget.endLocation);
    }

    if (mounted) {
      setState(() {
        _resolvedStart = startAddr;
        _resolvedEnd = endAddr;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: AppSizes.spacingXS),
          Text(
            'Route',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    final start = _resolvedStart ?? widget.startPlace;
    final end = _resolvedEnd ?? widget.endPlace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$start - $end',
          style: AppTextStyles.subtitle1.copyWith(
            color: AppColors.primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 12.0.sp,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: AppSizes.spacingXS),
        Text(
          'Route',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
