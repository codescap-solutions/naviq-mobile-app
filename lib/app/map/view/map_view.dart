import 'package:child_track/app/map/view_model/map_bloc.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:child_track/core/widgets/map_shimmer.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class MapViewWidget extends StatefulWidget {
  const MapViewWidget({
    super.key,
    required this.width,
    required this.height,
    this.interactive = true,
    this.currentPosition,
    this.markers,
    this.polylines,
    this.circles,
    this.isPolyLines = false,
    this.onMapCreated,
    this.myLocationEnabled = true,
    this.myLocationButtonEnabled = true,
    this.minZoom = 1.0,
    this.maxZoom = 20.0,
    this.useEagerGestures = false,
    this.onCameraMove,
    this.onMapTap,
  });
  final double width, height;
  final bool interactive, isPolyLines;
  final bool useEagerGestures;
  final void Function(CameraPosition)? onCameraMove;
  final LatLng? currentPosition;
  final List<Marker>? markers;
  final List<Polyline>? polylines;
  final Set<Circle>? circles;
  final void Function(GoogleMapController)? onMapCreated;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final double minZoom;
  final double maxZoom;
  final void Function(LatLng)? onMapTap;
  @override
  State<MapViewWidget> createState() => _MapViewWidgetState();
}

class _MapViewWidgetState extends State<MapViewWidget> {
  Map<PolylineId, Polyline> polylines = {};
  MapType currentMapType = MapType.normal;
  late CameraPosition _initialCameraPosition;

  @override
  void initState() {
    super.initState();
    getPolylines();
    _initialCameraPosition = CameraPosition(
      target:
          widget.currentPosition ??
          const LatLng(11.258753, 75.780410), // fallback
      zoom: 15,
    );
  }

  void _showMapTypeOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Map Type',
                style: TextStyle(fontSize: 18.0.sp, fontWeight: FontWeight.bold),
              ),
            ),
            _buildMapTypeOption(context, 'Normal', MapType.normal, Icons.map),
            _buildMapTypeOption(
              context,
              'Satellite',
              MapType.satellite,
              Icons.satellite,
            ),
            _buildMapTypeOption(
              context,
              'Hybrid',
              MapType.hybrid,
              Icons.layers,
            ),
            _buildMapTypeOption(
              context,
              'Terrain',
              MapType.terrain,
              Icons.terrain,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMapTypeOption(
    BuildContext context,
    String label,
    MapType mapType,
    IconData icon,
  ) {
    final isSelected = currentMapType == mapType;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.blue : Colors.grey[600]),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue : Colors.black87,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
      onTap: () {
        setState(() {
          currentMapType = mapType;
        });
        Navigator.pop(context);
      },
    );
  }

  @override
  void didUpdateWidget(MapViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh polylines when either markers or polylines actually change.
    // `markers`/`polylines` are rebuilt as new List instances on nearly
    // every parent rebuild (e.g. `markers.toList()` in home_page.dart), so a
    // reference check here (`!=`) was true on every single frame even when
    // the actual positions hadn't moved — for isPolyLines:true screens that
    // meant a fresh (billed) Directions API call every rebuild. Compare by
    // position instead so a same-content rebuild is a no-op.
    if (!_markersEqual(widget.markers, oldWidget.markers) ||
        !_polylinesEqual(widget.polylines, oldWidget.polylines)) {
      if (mounted) {
        getPolylines();
      }
    }
  }

  static bool _markersEqual(List<Marker>? a, List<Marker>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].markerId != b[i].markerId || a[i].position != b[i].position) {
        return false;
      }
    }
    return true;
  }

  static bool _polylinesEqual(List<Polyline>? a, List<Polyline>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].polylineId != b[i].polylineId) return false;
    }
    return true;
  }

  Future<void> getPolylines() async {
    if (!mounted) return;

    final Map<PolylineId, Polyline> initialPolylines = {};
    if (widget.polylines != null && widget.polylines!.isNotEmpty) {
      // Explicit polylines provided (trip detail mode) — use them directly
      for (var polyline in widget.polylines!) {
        initialPolylines[polyline.polylineId] = polyline;
      }
    } else if (widget.isPolyLines) {
      // No explicit polylines, but caller opted in (isPolyLines: true) — fetch
      // via Directions API from markers. Gated behind isPolyLines because this
      // used to fire unconditionally on every rebuild for ANY caller that
      // didn't pass polylines, including the home-screen live map (which just
      // shows a single child pin, no route needed). Since `markers` is
      // rebuilt as a new List every build there (home_page.dart's
      // `markers.toList()`), didUpdateWidget's reference check saw it as
      // "changed" on every single frame and re-hit the billed Directions API
      // continuously for as long as the screen was open — confirmed as the
      // cause of a ₹1000+/day Google Cloud Directions API spike while a trip
      // sat open for 21+ hours. Only screens that explicitly ask for a
      // computed route (isPolyLines: true) get this fallback now.
      try {
        final blocPolylines = await injector<MapBloc>().getPolyLines(
          widget.markers ?? [],
        );
        initialPolylines.addAll(blocPolylines);
      } catch (e) {
        // Ignore error if bloc fails
      }
    }

    polylines = initialPolylines;

    if (mounted) {
      // If MapBloc is still in MapInitial (no live tracking running),
      // emit MapLoaded so the GoogleMap widget renders.
      final mapBloc = injector<MapBloc>();
      if (mapBloc.state is! MapLoaded) {
        mapBloc.add(
          UpdateChildLocation(
            widget.currentPosition ?? const LatLng(11.258753, 75.780410),
          ),
        );
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: BlocProvider.value(
        value: injector<MapBloc>(),
        child: BlocBuilder<MapBloc, MapState>(
          builder: (context, state) {
            // Trip detail mode: explicit polylines provided — render map
            // immediately, no need to wait for MapLoaded from live tracking.
            // Live tracking mode: wait for MapLoaded so shimmer shows while
            // the tracking BLoC initialises.
            final hasExplicitPolylines =
                widget.polylines != null && widget.polylines!.isNotEmpty;
            final canRenderMap = state is MapLoaded || hasExplicitPolylines;

            if (canRenderMap) {
              return Stack(
                children: [
                  IgnorePointer(
                    ignoring: !widget.interactive,
                    child: RepaintBoundary(
                      child: GoogleMap(
                        onTap: (LatLng position) {
                          widget.onMapTap?.call(position);
                        },
                        mapType: currentMapType,
                        mapToolbarEnabled: true,
                        zoomControlsEnabled: true,
                        compassEnabled: false,
                        gestureRecognizers:
                            widget.interactive && widget.useEagerGestures
                            ? <Factory<OneSequenceGestureRecognizer>>{
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              }
                            : <Factory<OneSequenceGestureRecognizer>>{},
                        scrollGesturesEnabled: widget.interactive,
                        minMaxZoomPreference: MinMaxZoomPreference(
                          widget.minZoom,
                          widget.maxZoom,
                        ),
                        zoomGesturesEnabled: widget.interactive,
                        tiltGesturesEnabled: widget.interactive,
                        rotateGesturesEnabled: widget.interactive,
                        onMapCreated: (controller) {
                          injector<MapBloc>().add(MapCreated(controller));
                          widget.onMapCreated?.call(controller);
                        },
                        // Polylines: explicit ones take priority (trip detail),
                        // then fall back to BLoC-computed ones (live map).
                        polylines: () {
                          if (hasExplicitPolylines) {
                            final pts = widget.polylines!;
                            debugPrint('[MapViewWidget] passing ${pts.length} polyline(s) to GoogleMap');
                            for (var i = 0; i < pts.length; i++) {
                              debugPrint('[MapViewWidget]   polyline[$i].points.length = ${pts[i].points.length}');
                              if (pts[i].points.isNotEmpty) {
                                debugPrint('[MapViewWidget]   polyline[$i].first = ${pts[i].points.first}');
                                debugPrint('[MapViewWidget]   polyline[$i].last  = ${pts[i].points.last}');
                              }
                            }
                            return pts.toSet();
                          }
                          return Set<Polyline>.of(polylines.values);
                        }(),
                        circles: widget.circles ?? {},
                        initialCameraPosition: _initialCameraPosition,
                        markers: () {
                          if (widget.markers != null &&
                              widget.markers!.isNotEmpty) {
                            return widget.markers!.toSet();
                          }
                          if (state is MapLoaded) {
                            return state.markers.toSet();
                          }
                          return <Marker>{};
                        }(),
                        onCameraMove: widget.onCameraMove,
                        onCameraMoveStarted: () {},
                        onCameraIdle: () {},
                        myLocationEnabled: widget.myLocationEnabled,
                        myLocationButtonEnabled: widget.myLocationButtonEnabled,
                      ),
                    ),
                  ),
                  // Floating layers button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    right: 20,
                    child: InkWell(
                      onTap: () => _showMapTypeOptions(context),
                      child: CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        child: const Icon(Icons.layers, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            }
            return MapShimmer(width: widget.width, height: widget.height);
          },
        ),
      ),
    );
  }
}
