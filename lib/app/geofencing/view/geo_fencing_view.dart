import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/utils/responsive_font.dart';
import '../../../core/services/shared_prefs_service.dart';
import '../../../core/services/subscription_feature_gate.dart';
import '../../../core/di/injector.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../subscription/widgets/upgrade_restriction_dialog.dart';
import '../../home/view_model/bloc/homepage_bloc.dart';
import 'location_selections.dart';
import 'place_selection_view.dart';
import '../view_model/bloc/geofence_bloc.dart';
import '../view_model/bloc/geofence_event.dart';
import '../view_model/bloc/geofence_state.dart';
import '../model/geofence_model.dart';
import 'widgets/geoplace_card.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'widgets/preset_place_card_body.dart';
import 'package:child_track/core/widgets/geo_fencing_shimmer.dart';

class GeoFencingView extends StatefulWidget {
  final String? childId;
  final String? parentId;

  const GeoFencingView({super.key, this.childId, this.parentId});

  @override
  State<GeoFencingView> createState() => _GeoFencingViewState();
}

class _GeoFencingViewState extends State<GeoFencingView> {
  List<Geofence> _geofences = [];
  int _defaultRadius = 30;
  String? _lastDateParam;
  late final bool _isPrimaryParent;

  String _getChildName() {
    return SharedPrefsService().getString('child_name') ?? 'Ananya';
  }

  String _getChildEmoji() {
    final name = _getChildName().toLowerCase();
    if (name.contains('rohan')) return '👦';
    return '👧';
  }

  @override
  void initState() {
    super.initState();
    _isPrimaryParent = SharedPrefsService().isPrimaryParent;
    // Load default radius from SharedPreferences
    _defaultRadius = SharedPrefsService().getInt('default_radius') ?? 30;

    // Load geofences when the view is initialized
    if (widget.childId != null) {
      // Default to today's data on initial load
      final today = DateTime.now();
      final todayStr =
          "${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      _lastDateParam = todayStr;
      context.read<GeofenceBloc>().add(
        GetGeofencesRequested(childId: widget.childId!, date: todayStr),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Count how many geofences are active (locked)
    final activeCount = _geofences.where((g) => g.isLocked ?? false).length;

    final homeState = injector<HomepageBloc>().state;
    String? currentAddress;
    LatLng? currentLatLng;
    if (homeState is HomepageSuccess && homeState.currentLocation != null) {
      final loc = homeState.currentLocation!;
      currentLatLng = LatLng(loc.lat, loc.lng);
      currentAddress = loc.address;
    }

    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: figmaAppBar(context, title: 'Geofencing'),
      body: Column(
        children: [
          _buildChildHeaderRow(activeCount),
          Expanded(
            child: BlocConsumer<GeofenceBloc, GeofenceState>(
              listener: (context, state) {
                if (state is GeofencesLoaded) {
                  setState(() {
                    _geofences = state.geofences;
                  });
                } else if (state is GeofenceCreated) {
                  setState(() {
                    _geofences.add(state.geofence);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Geofence created successfully')),
                  );
                } else if (state is GeofenceUpdated) {
                  setState(() {
                    final index = _geofences.indexWhere(
                      (g) => g.id == state.geofence.id,
                    );
                    if (index != -1) _geofences[index] = state.geofence;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Geofence updated successfully')),
                  );
                } else if (state is GeofenceDeleted) {
                  setState(() {
                    _geofences.removeWhere((g) => g.id == state.geofenceId);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Geofence deleted successfully')),
                  );
                } else if (state is GeofenceLockToggled) {
                  setState(() {
                    final index = _geofences.indexWhere(
                      (g) => g.id == state.geofence.id,
                    );
                    if (index != -1) _geofences[index] = state.geofence;
                  });
                } else if (state is GeofenceError) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(state.message)));
                }
              },
              builder: (context, state) {
                if (state is GeofenceLoading) {
                  return GeoFencingShimmer();
                }

                if (state is GeofenceError) {
                  final message = state.message;
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            message,
                            style: TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 12.w),
                          ElevatedButton(
                            onPressed: () {
                              if (widget.childId != null) {
                                context.read<GeofenceBloc>().add(
                                  GetGeofencesRequested(
                                    childId: widget.childId!,
                                    date: _lastDateParam,
                                  ),
                                );
                              }
                            },
                            child: Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  child: ListView(
                    physics: BouncingScrollPhysics(),
                    children: [
                      SizedBox(height: 24.w),

                      // Fences List
                      if (_geofences.isNotEmpty) ...[
                        ..._geofences.map(
                          (geofence) => GeoPlaceCard(
                            title: geofence.name ?? "Unknown Place",
                            radius: geofence.radius ?? _defaultRadius,
                            toggleValue: geofence.isLocked ?? false,
                            category: geofence.category,
                            onTap: _isPrimaryParent
                                ? () => _navigateToLocationSelection(
                                    geofence: geofence,
                                  )
                                : () => AppSnackbar.showError(
                                    context,
                                    'Guardians have view-only access. Only primary parents can edit geofences.',
                                  ),
                            onToggle: (value) {
                              if (!_isPrimaryParent) {
                                AppSnackbar.showError(
                                  context,
                                  'Guardians have view-only access. Only primary parents can edit geofences.',
                                );
                                return;
                              }
                              if (geofence.id != null) {
                                context.read<GeofenceBloc>().add(
                                  ToggleGeofenceLockRequested(
                                    id: geofence.id!,
                                    isLocked: value,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Invalid geofence ID'),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ] else ...[
                        // Professional Quick Add / Preset Grid directly on main page
                        SizedBox(height: 16.w),
                        _buildPresetGridHeader(),
                        SizedBox(height: 8.w),
                        _buildPresetGridContent(),
                        SizedBox(height: 24.w),
                      ],

                      SizedBox(height: 24.w),

                      // Suggested Fences Section
                      _buildSuggestedFencesHeader(),
                      SizedBox(height: 8.w),
                      if (currentLatLng != null) ...[
                        _buildSuggestedFenceTile(
                          "Current Location (${_formatAddress(currentAddress)})",
                          currentLatLng,
                          isCurrentLocation: true,
                        ),
                        SizedBox(height: 8.w),
                      ],
                      _buildSuggestedFenceTile(
                        "${_getChildName()}'s School",
                        LatLng(12.9698, 77.7500),
                      ),

                      SizedBox(height: 80.w), // spacer for FAB
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // Plain circular "+" FAB (60px, #0069F9) — matches the Figma shape
      // family instead of a labeled pill button.
      floatingActionButton: _isPrimaryParent
          ? Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: SizedBox(
                width: 60.w,
                height: 60.w,
                child: FloatingActionButton(
                  onPressed: _navigateToPlaceSelection,
                  backgroundColor: Color(0xFF0069F9),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: CircleBorder(),
                  child: Icon(Icons.add_rounded, size: 28.w),
                ),
              ),
            )
          : null,
    );
  }

  /// Figma "Frame 2425": 42px band holding two 28px pills at x12 / gap 12.
  Widget _buildChildHeaderRow(int activeCount) {
    final pillText = FigmaText.poppins(14, weight: FontWeight.w700);
    return Container(
      color: Colors.white,
      height: 42.w,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      alignment: Alignment.topLeft,
      child: Row(
        children: [
          _headerPill(
            color: Color(0xFFEFF6FF),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${_getChildEmoji()} ${_getChildName()}",
                  style: pillText.copyWith(color: FigmaColors.primary),
                ),
                SizedBox(width: 4.w),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: FigmaColors.primary,
                  size: 20.w,
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          _headerPill(
            color: Color(0xFFEAF8F0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$activeCount active ${activeCount == 1 ? 'fence' : 'fences'}",
                  style: pillText.copyWith(color: Color(0xFF22C55E)),
                ),
                SizedBox(width: 4.w),
                Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 16.w),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPill({required Color color, required Widget child}) {
    return Container(
      height: 28.w,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14.w),
      ),
      child: child,
    );
  }

  /// Figma "SUGGESTED FENCES": 18px caption line, aligned with the cards.
  Widget _buildSuggestedFencesHeader() => _sectionCaption("SUGGESTED FENCES");

  Widget _sectionCaption(String text) => SizedBox(
    height: 18.w,
    child: Text(
      text,
      style: FigmaText.poppins(
        11,
        weight: FontWeight.w800,
        color: Color(0xFF94A3B8),
        lineHeight: 18,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _buildSuggestedFenceTile(
    String name,
    LatLng coordinates, {
    bool isCurrentLocation = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.w),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0C1D37).withValues(alpha: 0.02),
            blurRadius: 10.w,
            offset: Offset(0, 2.w),
          ),
        ],
      ),
      child: ListTile(
        minTileHeight: 50.w,
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w),
        onTap: () {
          if (!_isPrimaryParent) {
            AppSnackbar.showError(
              context,
              'Guardians have view-only access. Only primary parents can edit geofences.',
            );
            return;
          }
          if (!_canCreateNewGeofence()) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LocationSelectionScreen(
                childId: widget.childId,
                parentId: widget.parentId,
                selectedCategory: "other",
                customName: name.split('(').first.trim(),
                isCurrentLocation: isCurrentLocation,
                geofence: Geofence(
                  name: name.split('(').first.trim(),
                  address: name,
                  latitude: coordinates.latitude,
                  longitude: coordinates.longitude,
                ),
              ),
            ),
          ).then((_) {
            if (!mounted) return;
            if (widget.childId != null && _lastDateParam != null) {
              context.read<GeofenceBloc>().add(
                GetGeofencesRequested(
                  childId: widget.childId!,
                  date: _lastDateParam!,
                ),
              );
            }
            injector<HomepageBloc>().add(GetHomepageData());
          });
        },
        title: Text(
          name,
          style: GoogleFonts.poppins(
            fontSize: 14.0.sp,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0C1D37),
          ),
        ),
        trailing: Icon(
          CupertinoIcons.chevron_right,
          color: Color(0xFF94A3B8),
          size: 16.w,
        ),
      ),
    );
  }

  /// Returns true if a new geofence may be created under the current
  /// subscription tier's zone limit. Shows the upgrade dialog and returns
  /// false when the limit is already reached. Editing an existing geofence
  /// is never gated by this — only creation.
  bool _canCreateNewGeofence() {
    final limit = SubscriptionFeatureGate.geofenceLimit();
    if (_geofences.length < limit) return true;
    UpgradeRestrictionDialog.show(
      context,
      title: 'Geofence Limit Reached',
      message:
          'Your current plan allows up to $limit geofence zone${limit == 1 ? '' : 's'}. '
          'Upgrade to add more.',
      suggestedTier: SubscriptionFeatureGate.nextTier(),
    );
    return false;
  }

  void _navigateToLocationSelection({Geofence? geofence}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSelectionScreen(
          childId: widget.childId,
          parentId: widget.parentId,
          geofence: geofence,
        ),
      ),
    ).then((result) {
      if (!mounted) return;
      if (widget.childId != null && _lastDateParam != null) {
        context.read<GeofenceBloc>().add(
          GetGeofencesRequested(
            childId: widget.childId!,
            date: _lastDateParam!,
          ),
        );
      }

      if (result != null &&
          result is Map &&
          result['action'] == 'updated' &&
          result['geofence'] != null) {
        final updatedGeofence = result['geofence'] as Geofence;
        final homeBloc = injector<HomepageBloc>();
        final currentState = homeBloc.state;
        if (currentState is HomepageSuccess &&
            currentState.currentLocation != null) {
          if (geofence != null &&
              geofence.name != null &&
              currentState.currentLocation!.placeName == geofence.name) {
            homeBloc.add(
              UpdateCurrentLocationName(updatedGeofence.name ?? "Unknown"),
            );
          }
        }
      }

      injector<HomepageBloc>().add(GetHomepageData());
    });
  }

  void _navigateToPlaceSelection() {
    if (!_canCreateNewGeofence()) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceSelectionScreen(
        childId: widget.childId,
        parentId: widget.parentId,
      ),
    ).then((_) {
      if (!mounted) return;
      // Refresh geofences list on return
      if (widget.childId != null && _lastDateParam != null) {
        context.read<GeofenceBloc>().add(
          GetGeofencesRequested(
            childId: widget.childId!,
            date: _lastDateParam!,
          ),
        );
      }
      injector<HomepageBloc>().add(GetHomepageData());
    });
  }

  String _formatAddress(String? address) {
    if (address == null || address.isEmpty) return 'Unknown location';
    final parts = address.split(',');
    if (parts.length > 2) {
      return '${parts[0].trim()}, ${parts[1].trim()}';
    }
    return address;
  }

  Widget _buildPresetGridHeader() => _sectionCaption("QUICK ADD GEOFENCE");

  Widget _buildPresetGridContent() {
    return GridView.count(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10.w,
      crossAxisSpacing: 12.w,
      childAspectRatio: (MediaQuery.of(context).size.width - 40.w) / 2 / 100.w,
      children: [
        _buildPresetGridCard(
          label: "School",
          emoji: '🏫',
          circleBg: Color(0xFF0DBF75),
          category: "school",
        ),
        _buildPresetGridCard(
          label: "Coaching",
          emoji: '🎓',
          circleBg: Color(0xFFF5A623),
          category: "tuition",
        ),
        _buildPresetGridCard(
          label: "Grandma's",
          emoji: '👵',
          circleBg: Color(0xFFF03E3E),
          category: "other",
        ),
        _buildPresetGridCard(
          label: "Temple/Masjid",
          emoji: '⛪',
          circleBg: Color(0xFF0069F9),
          category: "other",
        ),
        _buildPresetGridCard(
          label: "Sports Ground",
          emoji: '🏏',
          circleBg: Color(0xFF003A8C),
          category: "other",
        ),
        _buildPresetGridCard(
          label: "Current Location",
          emoji: '📍',
          circleBg: Color(0xFF9BA4B5),
          category: "other",
          isCurrentLocation: true,
        ),
      ],
    );
  }

  Widget _buildPresetGridCard({
    required String label,
    required String emoji,
    required Color circleBg,
    required String category,
    bool isCurrentLocation = false,
  }) {
    final homeState = injector<HomepageBloc>().state;
    LatLng? currentLatLng;
    String? currentAddress;
    if (isCurrentLocation &&
        homeState is HomepageSuccess &&
        homeState.currentLocation != null) {
      final loc = homeState.currentLocation!;
      currentLatLng = LatLng(loc.lat, loc.lng);
      currentAddress = loc.address;
    }

    return GestureDetector(
      onTap: () {
        if (!_isPrimaryParent) {
          AppSnackbar.showError(
            context,
            'Guardians have view-only access. Only primary parents can edit geofences.',
          );
          return;
        }
        if (!_canCreateNewGeofence()) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LocationSelectionScreen(
              childId: widget.childId,
              parentId: widget.parentId,
              selectedCategory: category,
              customName: label,
              isCurrentLocation: isCurrentLocation,
              geofence: currentLatLng != null
                  ? Geofence(
                      name: label,
                      address: currentAddress ?? 'Current Location',
                      latitude: currentLatLng.latitude,
                      longitude: currentLatLng.longitude,
                    )
                  : null,
            ),
          ),
        ).then((_) {
          if (!mounted) return;
          if (widget.childId != null && _lastDateParam != null) {
            context.read<GeofenceBloc>().add(
              GetGeofencesRequested(
                childId: widget.childId!,
                date: _lastDateParam!,
              ),
            );
          }
          injector<HomepageBloc>().add(GetHomepageData());
        });
      },
      child: PresetPlaceCardBody(label: label, emoji: emoji, color: circleBg),
    );
  }
}
