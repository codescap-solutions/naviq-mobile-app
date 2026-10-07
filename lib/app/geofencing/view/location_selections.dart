import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/widgets/figma_toggle.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';
import '../../map/view/map_view.dart';
import '../view_model/bloc/geofence_bloc.dart';
import '../view_model/bloc/geofence_event.dart';
import '../view_model/bloc/geofence_state.dart';
import '../model/geofence_model.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class LocationSelectionScreen extends StatefulWidget {
  final String? childId;
  final String? parentId;
  final Geofence? geofence;
  final String? selectedCategory;
  final String? customName;
  final bool isCurrentLocation;

  const LocationSelectionScreen({
    super.key,
    this.childId,
    this.parentId,
    this.geofence,
    this.selectedCategory,
    this.customName,
    this.isCurrentLocation = false,
  });

  @override
  State<LocationSelectionScreen> createState() =>
      _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final TextEditingController _searchController = TextEditingController();
  bool _showSuggestions = false;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};
  bool _isMapReady = false;
  int _defaultRadius = 30;
  String? _selectedAddress;
  BitmapDescriptor? _centerDotIcon;

  static const LatLng _initialPosition = LatLng(12.9716, 77.5946); // Bengaluru

  @override
  void initState() {
    super.initState();
    _buildCenterDotIcon();
    // Load default radius from SharedPreferences
    _defaultRadius = SharedPrefsService().getInt('default_radius') ?? 30;

    // If we are editing an existing geofence, show its marker initially
    if (widget.geofence != null) {
      final g = widget.geofence!;
      if (g.latitude != null && g.longitude != null) {
        final position = LatLng(g.latitude!, g.longitude!);
        final radius = (g.radius ?? _defaultRadius).toDouble();

        _markers.add(
          Marker(
            markerId: const MarkerId('selected_location'),
            position: position,
            infoWindow: InfoWindow(title: g.name ?? 'Selected Location'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            onTap: () => _openFormSheet(position),
          ),
        );
        _updateCircle(position, radius);
        _searchController.text = g.name ?? '';

        // Open the edit sheet automatically when screen is opened for editing
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openFormSheet(position);
        });
      }
    } else if (widget.childId != null) {
      // Fetch the child's location natively
      context.read<GeofenceBloc>().add(
        FetchChildLocationRequested(childId: widget.childId!),
      );
    }
  }

  /// Figma centre marker: a flat 14px #0069F9 dot.
  Future<void> _buildCenterDotIcon() async {
    const double size = 14;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()..color = const Color(0xFF0069F9),
    );
    final img = await recorder.endRecording().toImage(
      (size * 3).toInt(),
      (size * 3).toInt(),
    );
    // Draw at 3x for crispness and ask the map to show it at 14 logical px.
    final recorder3 = ui.PictureRecorder();
    final canvas3 = Canvas(recorder3);
    canvas3.scale(3);
    canvas3.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()..color = const Color(0xFF0069F9),
    );
    img.dispose();
    final img3 = await recorder3.endRecording().toImage(
      (size * 3).toInt(),
      (size * 3).toInt(),
    );
    final bytes = await img3.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null || !mounted) return;
    setState(() {
      _centerDotIcon = BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        width: size,
        height: size,
      );
      // Markers added before the icon was ready (edit mode) pick it up too.
      final restyled = _markers
          .map(
            (m) => m.copyWith(
              iconParam: _centerDotIcon,
              anchorParam: const Offset(0.5, 0.5),
            ),
          )
          .toList();
      _markers
        ..clear()
        ..addAll(restyled);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LatLng> _generateCirclePoints(LatLng center, double radiusInMeters) {
    final List<LatLng> points = [];
    const int segments = 120; // number of points along the circle
    const double earthRadius = 6378137.0; // in meters
    final double latRad = center.latitude * math.pi / 180.0;
    final double lngRad = center.longitude * math.pi / 180.0;
    final double r = radiusInMeters / earthRadius;

    for (int i = 0; i <= segments; i++) {
      final double theta = 2.0 * math.pi * i / segments;
      final double pointLatRad = math.asin(
        math.sin(latRad) * math.cos(r) +
            math.cos(latRad) * math.sin(r) * math.cos(theta),
      );
      final double pointLngRad =
          lngRad +
          math.atan2(
            math.sin(theta) * math.sin(r) * math.cos(latRad),
            math.cos(r) - math.sin(latRad) * math.sin(pointLatRad),
          );
      points.add(
        LatLng(pointLatRad * 180.0 / math.pi, pointLngRad * 180.0 / math.pi),
      );
    }
    return points;
  }

  void _updateCircle(LatLng position, double radius) {
    final points = _generateCirclePoints(position, radius);
    setState(() {
      _circles.clear();
      _circles.add(
        Circle(
          circleId: const CircleId('geofence_fill'),
          center: position,
          radius: radius,
          fillColor: const Color(0xFF0069F9).withValues(alpha: 0.12),
          strokeColor: Colors.transparent,
        ),
      );

      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('geofence_dashed_border'),
          points: points,
          color: const Color(0xFF0069F9),
          width: 2,
          patterns: [PatternItem.dash(12), PatternItem.gap(8)],
        ),
      );
    });
  }

  void _addMarker(LatLng position) {
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          infoWindow: const InfoWindow(title: 'Selected Location'),
          icon:
              _centerDotIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          onTap: () => _openFormSheet(position),
        ),
      );
    });
    _updateCircle(position, _defaultRadius.toDouble());
  }

  Future<void> _openFormSheet(LatLng position) async {
    setState(() {
      _showSuggestions = false;
    });

    final currentRadius = _circles.isNotEmpty
        ? _circles.first.radius
        : _defaultRadius.toDouble();

    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GeoFenceFormSheet(
        latitude: position.latitude,
        longitude: position.longitude,
        childId: widget.childId ?? '',
        parentId: widget.parentId ?? '',
        geofence: widget.geofence,
        category: widget.selectedCategory,
        customName: widget.customName,
        address:
            _selectedAddress ??
            widget.geofence?.address ??
            "${widget.customName ?? 'Custom Place'} · Fenced Location",
        initialRadius: currentRadius.toInt(),
        onRadiusChanged: (newRadius) {
          _updateCircle(position, newRadius);
        },
      ),
    );
    if (result != null) {
      if (!mounted) return;
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: figmaAppBar(
        context,
        title: 'Geoguard',
        titleColor: const Color(0xFF2D3035),
      ),
      body: BlocListener<GeofenceBloc, GeofenceState>(
        listener: (context, state) {
          if (state is GeofenceError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          } else if (state is PlaceCoordinatesLoaded) {
            _addMarker(state.coordinates);
            if (_isMapReady) {
              _controller.future.then((controller) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(state.coordinates, 16),
                );
              });
            }
            // Automatically open bottom sheet for the suggestions coordinates
            _openFormSheet(state.coordinates);
          } else if (state is ChildLocationLoaded) {
            _addMarker(state.coordinates);
            if (_isMapReady) {
              _controller.future.then((controller) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(state.coordinates, 16),
                );
              });
            }
            if (widget.isCurrentLocation) {
              _openFormSheet(state.coordinates);
            }
          }
        },
        child: Stack(
          children: [
            MapViewWidget(
              key: const ValueKey('location_map_selection'),
              width: double.infinity,
              height: double.infinity,
              interactive: true,
              myLocationEnabled: false,
              minZoom: 0.0,
              maxZoom: 20,
              myLocationButtonEnabled: false,
              markers: _markers.toList(),
              circles: _circles,
              polylines: _polylines.toList(),
              onMapCreated: (controller) async {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                  setState(() {
                    _isMapReady = true;
                  });
                  final geofenceBloc = context.read<GeofenceBloc>();
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (!mounted) return;

                  final state = geofenceBloc.state;

                  if (widget.geofence != null &&
                      widget.geofence!.latitude != null &&
                      widget.geofence!.longitude != null) {
                    controller.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(
                          widget.geofence!.latitude!,
                          widget.geofence!.longitude!,
                        ),
                        16,
                      ),
                    );
                  } else if (state is ChildLocationLoaded) {
                    // Handled by BlocListener
                  } else {
                    controller.animateCamera(
                      CameraUpdate.newLatLngZoom(_initialPosition, 14),
                    );
                  }
                }
              },
              onMapTap: (position) async {
                _addMarker(position);
                await Future.delayed(const Duration(milliseconds: 150));
                _openFormSheet(position);
              },
            ),

            /// Search Bar
            Positioned(
              top: 7,
              left: 14,
              right: 14,
              child: Column(
                children: [
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 19),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(44),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        SvgPicture.asset(
                          'assets/icons/geo_search.svg',
                          width: 15,
                          height: 15,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.poppins(
                              fontSize: 12.0.sp,
                              fontWeight: FontWeight.w400,
                              height: 20 / 12,
                              letterSpacing: 0.2,
                              color: const Color(0xFF2D3035),
                            ),
                            decoration: InputDecoration(
                              hintText: "search location",
                              hintStyle: GoogleFonts.poppins(
                                fontSize: 12.0.sp,
                                fontWeight: FontWeight.w400,
                                height: 20 / 12,
                                letterSpacing: 0.2,
                                color: const Color(0xFF9BA4B5),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              isCollapsed: true,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                context.read<GeofenceBloc>().add(
                                  SearchLocationSuggestionsRequested(
                                    query: value,
                                  ),
                                );
                                setState(() {
                                  _showSuggestions = true;
                                });
                              } else {
                                setState(() {
                                  _showSuggestions = false;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showSuggestions)
                    BlocBuilder<GeofenceBloc, GeofenceState>(
                      builder: (context, state) {
                        if (state is LocationSuggestionsLoaded) {
                          return Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0C1D37,
                                  ).withValues(alpha: 0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: state.suggestions.length,
                              itemBuilder: (context, index) {
                                final suggestion = state.suggestions[index];
                                return ListTile(
                                  title: Text(
                                    suggestion.mainText ?? "Unknown",
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.0.sp,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF0C1D37),
                                    ),
                                  ),
                                  subtitle: Text(
                                    suggestion.description ??
                                        "Unknown location",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.0.sp,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  onTap: () {
                                    _searchController.text =
                                        suggestion.mainText!;
                                    _selectedAddress =
                                        "${suggestion.mainText} · ${suggestion.description}";
                                    setState(() {
                                      _showSuggestions = false;
                                    });

                                    // Emit event to fetch place coordinates via BLoC
                                    context.read<GeofenceBloc>().add(
                                      GetPlaceCoordinatesRequested(
                                        placeId: suggestion.placeId!,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C1D37).withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Text(
            "zoom in and pick the location you want to fence",
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.0.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

class GeoFenceFormSheet extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String childId;
  final String parentId;
  final Geofence? geofence;
  final String? category;
  final String? customName;
  final String? address;
  final int? initialRadius;
  final ValueChanged<double>? onRadiusChanged;

  const GeoFenceFormSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.childId,
    required this.parentId,
    this.geofence,
    this.category,
    this.customName,
    this.address,
    this.initialRadius,
    this.onRadiusChanged,
  });

  @override
  State<GeoFenceFormSheet> createState() => _GeoFenceFormSheetState();
}

class _GeoFenceFormSheetState extends State<GeoFenceFormSheet> {
  final List<int> radiusSteps = [50, 100, 200, 500, 1000];
  int _sliderIndex = 0;
  int _radius = 50;

  bool _alertOnEntry = true;
  bool _alertOnExit = true;
  bool _alertIfIdle = false;
  late final TextEditingController _nameController;

  int _findClosestStep(int radius) {
    int closestIndex = 0;
    int minDiff = (radius - radiusSteps[0]).abs();
    for (int i = 1; i < radiusSteps.length; i++) {
      int diff = (radius - radiusSteps[i]).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.customName ?? widget.geofence?.name ?? "Custom Place",
    );
    _nameController.addListener(() {
      setState(() {});
    });

    // Prefill fields when editing
    if (widget.geofence != null) {
      final g = widget.geofence!;
      _radius = g.radius ?? 50;
      _sliderIndex = _findClosestStep(_radius);
      _radius = radiusSteps[_sliderIndex];
      _alertOnEntry = g.isLocked ?? true;
      _alertOnExit = true;
      _alertIfIdle = false;
    } else {
      _radius = widget.initialRadius ?? 50;
      _sliderIndex = _findClosestStep(_radius);
      _radius = radiusSteps[_sliderIndex];
      _alertOnEntry = true;
      _alertOnExit = true;
      _alertIfIdle = false;
    }

    // Notify map screen of initial radius step
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRadiusChanged?.call(_radius.toDouble());
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String? category, String? customName) {
    final cat = category?.toLowerCase();
    final name = customName?.toLowerCase() ?? '';
    if (cat == 'school' || name.contains('school')) {
      return Icons.school_rounded;
    } else if (cat == 'tuition' || name.contains('coaching')) {
      return Icons.school_outlined;
    } else if (name.contains("grandma")) {
      return Icons.face_retouching_natural_rounded;
    } else if (name.contains("temple") ||
        name.contains("masjid") ||
        name.contains("church")) {
      return Icons.account_balance_rounded;
    } else if (name.contains("sports") ||
        name.contains("ground") ||
        name.contains("play")) {
      return Icons.sports_cricket_rounded;
    } else if (name.contains("location") || name.contains("current")) {
      return Icons.location_on_rounded;
    } else if (cat == 'home' || name.contains('home')) {
      return Icons.home_rounded;
    }
    return Icons.place_rounded;
  }

  Color _getCategoryColor(String? category, String? customName) {
    final cat = category?.toLowerCase();
    final name = customName?.toLowerCase() ?? '';
    if (cat == 'school' || name.contains('school')) {
      return const Color(0xFF22C55E);
    } else if (cat == 'tuition' || name.contains('coaching')) {
      return const Color(0xFFF59E0B);
    } else if (name.contains("grandma")) {
      return const Color(0xFFEF4444);
    } else if (name.contains("temple") ||
        name.contains("masjid") ||
        name.contains("church")) {
      return const Color(0xFF8B5CF6);
    } else if (name.contains("sports") ||
        name.contains("ground") ||
        name.contains("play")) {
      return const Color(0xFF0066FF);
    } else if (name.contains("location") || name.contains("current")) {
      return const Color(0xFF64748B);
    } else if (cat == 'home' || name.contains('home')) {
      return const Color(0xFF0066FF);
    }
    return const Color(0xFF64748B);
  }

  Widget _buildToggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16.0.sp,
              fontWeight: FontWeight.w400,
              height: 24 / 16,
              letterSpacing: 0.2,
              color: const Color(0xFF0F1320),
            ),
          ),
          FigmaToggle(
            value: value,
            onChanged: onChanged,
            width: 48,
            height: 28,
            knob: 22,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GeofenceBloc, GeofenceState>(
      listener: (context, state) {
        if (state is GeofenceCreated) {
          Navigator.pop(context, {
            "id": state.geofence.id,
            "name": state.geofence.name,
            "category": state.geofence.category,
            "latitude": state.geofence.latitude,
            "longitude": state.geofence.longitude,
            "radius": state.geofence.radius,
          });
        } else if (state is GeofenceUpdated) {
          Navigator.pop(context, {
            "id": state.geofence.id,
            "name": state.geofence.name,
            "category": state.geofence.category,
            "latitude": state.geofence.latitude,
            "longitude": state.geofence.longitude,
            "radius": state.geofence.radius,
          });
        } else if (state is GeofenceDeleted) {
          Navigator.pop(context, {"deleted": true, "id": state.geofenceId});
        } else if (state is GeofenceError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle (Figma: 40x4 #9BA4B5)
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 4,
                  color: const Color(0xFF9BA4B5),
                ),
              ),
              const SizedBox(height: 14),

              // Title: Poppins Bold 24/28 — still editable, just styled as
              // plain text like Figma (no underline, no icon badge).
              TextField(
                controller: _nameController,
                style: GoogleFonts.poppins(
                  fontSize: 24.0.sp,
                  fontWeight: FontWeight.w700,
                  height: 28 / 24,
                  color: const Color(0xFF0F1320),
                ),
                decoration: InputDecoration(
                  hintText: "Place Name",
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 24.0.sp,
                    fontWeight: FontWeight.w700,
                    height: 28 / 24,
                    color: const Color(0xFF9BA4B5),
                  ),
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              Text(
                widget.address ?? widget.geofence?.address ?? "Fenced Location",
                style: GoogleFonts.poppins(
                  fontSize: 12.0.sp,
                  fontWeight: FontWeight.w400,
                  height: 20 / 12,
                  letterSpacing: 0.2,
                  color: const Color(0xFF9BA4B5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),

              // Radius Slider Section
              Text(
                "Fence Radius",
                style: GoogleFonts.poppins(
                  fontSize: 14.0.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: const Color(0xFF0F1320),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: const Color(0xFF0069F9),
                  inactiveTrackColor: const Color(0xFFDDE1EA),
                  thumbColor: const Color(0xFF0069F9),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 11,
                    elevation: 0,
                    pressedElevation: 0,
                  ),
                  overlayColor: const Color(0xFF0069F9).withValues(alpha: 0.12),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  activeTickMarkColor: Colors.transparent,
                  inactiveTickMarkColor: Colors.transparent,
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: _sliderIndex.toDouble(),
                  min: 0,
                  max: 4,
                  divisions: 4,
                  onChanged: (val) {
                    setState(() {
                      _sliderIndex = val.toInt();
                      _radius = radiusSteps[_sliderIndex];
                    });
                    widget.onRadiusChanged?.call(_radius.toDouble());
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: radiusSteps.map((step) {
                    final label = step >= 1000
                        ? "${(step / 1000).toStringAsFixed(0)}km"
                        : "${step}m";
                    final index = radiusSteps.indexOf(step);
                    final isSelected = index == _sliderIndex;
                    return Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 12.0.sp,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        height: 20 / 12,
                        letterSpacing: 0.2,
                        color: isSelected
                            ? Colors.black
                            : const Color(0xFF9BA4B5),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Alerts — three plain rows, no heading or dividers (Figma)
              _buildToggleRow(
                title: "Alert on Entry",
                value: _alertOnEntry,
                onChanged: (val) {
                  setState(() {
                    _alertOnEntry = val;
                  });
                },
              ),
              _buildToggleRow(
                title: "Alert on Exit",
                value: _alertOnExit,
                onChanged: (val) {
                  setState(() {
                    _alertOnExit = val;
                  });
                },
              ),
              _buildToggleRow(
                title: "Alert if Idle > 30 min",
                value: _alertIfIdle,
                onChanged: (val) {
                  setState(() {
                    _alertIfIdle = val;
                  });
                },
              ),
              const SizedBox(height: 28),

              // Save Button
              BlocBuilder<GeofenceBloc, GeofenceState>(
                builder: (context, state) {
                  final isLoading = state is GeofenceLoading;
                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0069F9),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isLoading ? null : _handleSaveGeofence,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              "Save Fence",
                              style: GoogleFonts.poppins(
                                fontSize: 16.0.sp,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                                letterSpacing: 0.2,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  );
                },
              ),

              if (widget.geofence != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(
                        color: Color(0xFFFCA5A5),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      _showDeleteConfirmation(context);
                    },
                    child: Text(
                      "Delete Geofence",
                      style: GoogleFonts.poppins(
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dlgContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Delete Geofence',
          style: GoogleFonts.poppins(
            fontSize: 18.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.geofence?.name}"?',
          style: GoogleFonts.poppins(
            fontSize: 14.0.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgContext),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dlgContext);
              if (widget.geofence?.id != null) {
                context.read<GeofenceBloc>().add(
                  DeleteGeofenceRequested(id: widget.geofence!.id!),
                );
              }
            },
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSaveGeofence() {
    final name = _nameController.text.trim().isEmpty
        ? (widget.customName ?? widget.geofence?.name ?? "Custom Place")
        : _nameController.text.trim();
    final category = widget.category ?? widget.geofence?.category ?? "other";

    if (widget.geofence != null && widget.geofence!.id != null) {
      final updateRequest = UpdateGeofenceRequest(
        name: name,
        category: category,
        radius: _radius,
        latitude: widget.latitude,
        longitude: widget.longitude,
        alertOnEntry: _alertOnEntry,
        alertOnExit: _alertOnExit,
        alertIfIdle: _alertIfIdle,
      );

      if (widget.geofence!.isLocked != _alertOnEntry) {
        context.read<GeofenceBloc>().add(
          ToggleGeofenceLockRequested(
            id: widget.geofence!.id!,
            isLocked: _alertOnEntry,
          ),
        );
      }

      context.read<GeofenceBloc>().add(
        UpdateGeofenceRequested(
          id: widget.geofence!.id!,
          request: updateRequest,
        ),
      );
      return;
    }

    // Defense-in-depth: the entry points that push this screen already
    // block creation once the tier's zone limit is hit, but re-check here
    // against the bloc's last known list in case it changed meanwhile
    // (e.g. created from another device/tab while this sheet was open).
    final geofenceState = context.read<GeofenceBloc>().state;
    if (geofenceState is GeofencesLoaded) {
      final limit = SubscriptionFeatureGate.geofenceLimit();
      if (geofenceState.geofences.length >= limit) {
        UpgradeRestrictionDialog.show(
          context,
          title: 'Geofence Limit Reached',
          message:
              'Your current plan allows up to $limit geofence zone${limit == 1 ? '' : 's'}. '
              'Upgrade to add more.',
          suggestedTier: SubscriptionFeatureGate.nextTier(),
        );
        return;
      }
    }

    final request = CreateGeofenceRequest(
      name: name,
      category: category,
      radius: _radius,
      childId: widget.childId,
      parentId: widget.parentId,
      latitude: widget.latitude,
      longitude: widget.longitude,
      isLocked: _alertOnEntry,
      alertOnEntry: _alertOnEntry,
      alertOnExit: _alertOnExit,
      alertIfIdle: _alertIfIdle,
    );

    context.read<GeofenceBloc>().add(CreateGeofenceRequested(request: request));
  }
}
