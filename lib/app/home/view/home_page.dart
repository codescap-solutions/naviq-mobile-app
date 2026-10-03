import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/app/home/model/child_tracking_snapshot.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:http/http.dart' as http;
import 'package:child_track/core/navigation/route_names.dart';
import 'package:flutter/services.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/app/home/model/home_model.dart';
import 'package:child_track/app/subscription/view_model/subscription_repository.dart';
import 'package:child_track/app/map/view/map_view.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../geofencing/view/geo_fencing_view.dart';
import '../../geofencing/view_model/bloc/geofence_bloc.dart';
import '../../geofencing/view_model/bloc/geofence_event.dart';
import '../../settings/view/settings_view.dart';
import '../../settings/view/devices_view.dart';
import '../../notification/view/notification_page.dart';
import '../../social_apps/view/social_apps_view.dart';
import '../../explore/view/explore_view.dart';
import '../../addplace/model/saved_place_model.dart';
import '../../addplace/service/saved_places_service.dart';
import 'package:child_track/app/profile/view/profile_view.dart';
import '../../chat/view/chat_screen.dart';
import '../../chat/view_model/bloc/chat_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geocoding/geocoding.dart';
import '../../social_apps/view_model/time_limit_repository.dart';
import '../../childapp/view_model/repository/logout_request_repository.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';
import 'package:child_track/app/subscription/widgets/subscription_popup_sheet.dart';
import 'package:child_track/app/subscription/models/subscription_plan.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final SharedPrefsService _sharedPrefsService = injector<SharedPrefsService>();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // ── Map-First UX ─────────────────────────────────────────────────────────
  late final ScrollController _homeScrollController;
  // 0 = map fully visible, 1 = map fully washed out. Driven by the home scroll
  // offset; a ValueNotifier so only the overlay repaints per scroll frame.
  final ValueNotifier<double> _mapFadeAmount = ValueNotifier<double>(0);
  final GlobalKey<_HomeMapBackgroundState> _mapBackgroundKey = GlobalKey();
  double _mapHeightFraction =
      0.50; // Initial height (Expanded) — matches the Figma reference (~50% map on first load, with the location/Scroll/GeoGuard/Route-Map cards already visible underneath without scrolling)
  // True for the duration of an active user-driven scroll (drag or the
  // momentum fling after release). The map-height snap this drives
  // (_onHomeScroll) used to always animate over 300ms via AnimatedContainer
  // — including while the same scroll gesture was still moving the list
  // underneath it, so the sliver's own height was changing on its own
  // 300ms curve at the same time the user's finger was actively scrolling
  // it. Two competing motions on the same surface is exactly what "not
  // smooth" / stuttery scrolling looks like. Skipping the animation (jumping
  // straight to the target height) while this is true removes that fight;
  // the 300ms easing is still worth keeping for the FAB/recenter-triggered
  // snap, which happens with no finger on the screen.
  bool _isUserDraggingScroll = false;
  // ─────────────────────────────────────────────────────────────────────────

  StreamSubscription? _notificationSubscription;
  StreamSubscription? _foregroundSubscription;
  Map<String, dynamic>? _activeSharedChildData;
  bool _viewingSharedChild = false;
  bool _isLocationShareSheetOpen = false;
  bool _isTimeExtensionSheetOpen = false;
  bool _isLogoutRequestSheetOpen = false;
  Timer? _sharedChildTimer;
  DateTime? _lastResumeRefreshAt;

  late final SavedPlacesService _savedPlacesService;
  List<SavedPlace> _savedPlaces = [];

  int _refreshProgress = 0;
  bool _isRefreshing = false;
  Timer? _progressTimer;
  String? _currentLoadedChildId;

  void _onHomeScroll() {
    if (!mounted) return;
    final offset = _homeScrollController.offset;
    _mapFadeAmount.value = (offset / 260).clamp(0.0, 1.0);
    // The map used to shrink in steps (0.50 -> 0.35 -> 0.20 of the screen) as
    // the list scrolled. It's now pinned behind the scrolling content and just
    // fades out (see _HomeMapHeaderDelegate), so the step logic is disabled:
    /*
    double targetFraction = _mapHeightFraction;

    if (_mapHeightFraction == 0.50) {
      // Collapse threshold — was checking against 0.92 here, which the
      // initial value (set above) never equals, so this branch never
      // matched and the map never collapsed on scroll at all. Confirmed
      // live: scrolling the location card up did nothing until this was
      // fixed to check the actual initial fraction.
      if (offset > 60) {
        targetFraction = 0.35;
      }
    } else if (_mapHeightFraction == 0.35) {
      // Collapse or Expand thresholds
      if (offset > 240) {
        targetFraction = 0.20;
      } else if (offset < 40) {
        targetFraction = 0.50;
      }
    } else if (_mapHeightFraction == 0.20) {
      // Expand threshold
      if (offset < 160) {
        targetFraction = 0.35;
      }
    }

    if (targetFraction != _mapHeightFraction) {
      setState(() {
        _mapHeightFraction = targetFraction;
      });
    }
    */
  }

  void _startRefreshProgress() {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _refreshProgress = 0;
    });

    final childId = _sharedPrefsService.getString('child_id');

    void fetchLatest() {
      injector<HomepageBloc>().add(const GetHomepageData());
      if (childId != null) {
        final now = DateTime.now();
        final todayStr =
            "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
        context.read<GeofenceBloc>().add(
          GetGeofencesRequested(childId: childId, date: todayStr),
        );
      }
    }

    if (childId == null) {
      fetchLatest();
    } else {
      // Ask the child device for a fresh GPS/battery fix before re-reading
      // the server's cached snapshot — otherwise this refresh button just
      // re-serves whatever was already stored, which stays stale for hours
      // while the child device is stationary (see distanceFilter in
      // tracking_profile_manager.dart) or was offline until moments ago.
      // POST parent/refresh-child silently pushes FORCE_REFRESH_DATA to the
      // child app (server: notification.service.requestChildLocationUpdate),
      // which takes a one-shot high-accuracy fix ignoring distanceFilter and
      // uploads it (child side: firebase_notification_service.dart
      // _performForceRefresh). That round trip isn't instant, so fetchLatest
      // is delayed a few seconds to give it a real chance to land instead of
      // racing it — GetHomepageData still fires either way so the refresh
      // button never hangs even if the push fails or the device stays
      // unreachable.
      injector<HomeRepository>()
          .refreshChildLiveStatus(childId: childId)
          .catchError((e) {
            AppLogger.error('refresh-child request failed: $e');
            return BaseResponse.error(message: e.toString());
          })
          .whenComplete(() {
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) fetchLatest();
            });
          });
    }

    _loadSavedPlaces();

    _progressTimer = Timer.periodic(const Duration(milliseconds: 15), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_refreshProgress < 90) {
          _refreshProgress += 1;
        }
      });
    });
  }

  void _finishRefreshProgress() {
    if (!_isRefreshing) return;

    _progressTimer?.cancel();

    _progressTimer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_refreshProgress < 100) {
          _refreshProgress += 2;
          if (_refreshProgress > 100) _refreshProgress = 100;
        } else {
          timer.cancel();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() {
                _isRefreshing = false;
                _refreshProgress = 0;
              });
            }
          });
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _savedPlacesService = injector<SavedPlacesService>();
    _currentLoadedChildId = _sharedPrefsService.getString('child_id');
    _loadSavedPlaces();

    _homeScrollController = ScrollController();
    _homeScrollController.addListener(_onHomeScroll);
    // ─────────────────────────────────────────────────────────────────────

    // Fetch home data once on initialization
    injector<HomepageBloc>().add(GetHomepageData());

    // Preload subscription plans
    injector<SubscriptionRepository>().getPlans();

    // Listen to notification taps
    _notificationSubscription = injector<FirebaseNotificationService>()
        .notificationTapStream
        .listen((message) {
          AppLogger.info('🔥 [FCM TAP] Received message: data=${message.data}');
          if (message.data['type'] == 'location_share_request') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showLocationShareApprovalSheet(message.data);
              }
            });
          } else if (message.data['type'] == 'location_share_accepted') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _handleIncomingLocationShareAccepted(message.data);
              }
            });
          } else if (message.data['type'] == 'TIME_EXTENSION_REQUEST') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showTimeExtensionApprovalSheet(message.data);
              }
            });
          } else if (message.data['type'] == 'LOGOUT_REQUEST') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showLogoutApprovalSheet(message.data);
              }
            });
          }
        });

    // Listen to foreground notifications
    _foregroundSubscription = injector<FirebaseNotificationService>()
        .messageStream
        .listen((message) {
          AppLogger.info(
            '🔥 [FCM FG STREAM] Received message: data=${message.data}',
          );
          print('🔥 [FCM FG STREAM] Received message: data=${message.data}');
          if (message.data['type'] == 'location_share_request') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showLocationShareApprovalSheet(message.data);
              }
            });
          } else if (message.data['type'] == 'location_share_accepted') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _handleIncomingLocationShareAccepted(message.data);
              }
            });
          } else if (message.data['type'] == 'TIME_EXTENSION_REQUEST') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showTimeExtensionApprovalSheet(message.data);
              }
            });
          } else if (message.data['type'] == 'LOGOUT_REQUEST') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showLogoutApprovalSheet(message.data);
              }
            });
          }
        });

    // Check if there is a pending request on startup
    _checkAndShowPendingLocationRequest();

    // Extract navigation arguments for pre-selected tab index
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final args =
            ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
        if (args != null && args['initialIndex'] != null) {
          setState(() {
            _currentIndex = args['initialIndex'] as int;
          });
        }
      }
    });

    _sharedChildTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _viewingSharedChild) {
        setState(() {});
      }
    });
  }

  Future<void> _loadSavedPlaces() async {
    final childId = _sharedPrefsService.getString('child_id');
    final places = await _savedPlacesService.getSavedPlaces(childId: childId);
    if (mounted) {
      setState(() {
        _savedPlaces = places;
      });
    }
  }

  SavedPlace? _findMatchingPlace(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    // Tolerance for float comparison (approx 110 meters)
    const double tolerance = 0.001;

    try {
      return _savedPlaces.firstWhere((place) {
        return (place.latitude - lat).abs() < tolerance &&
            (place.longitude - lng).abs() < tolerance;
      });
    } catch (e) {
      return null;
    }
  }

  String _getRemainingTimeText(dynamic expiresAtInput) {
    if (expiresAtInput == null) return 'No expiry time';
    DateTime expiresAt;
    if (expiresAtInput is DateTime) {
      expiresAt = expiresAtInput;
    } else if (expiresAtInput is String) {
      expiresAt = DateTime.tryParse(expiresAtInput) ?? DateTime.now();
    } else {
      return 'Invalid expiry';
    }

    final duration = expiresAt.difference(DateTime.now());
    if (duration.isNegative) {
      return 'Expired';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m remaining';
    } else {
      return '${minutes}m remaining';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _sharedChildTimer?.cancel();
    _sheetController.dispose();
    _homeScrollController.removeListener(_onHomeScroll);
    _homeScrollController.dispose();
    _mapFadeAmount.dispose();
    _notificationSubscription?.cancel();
    _foregroundSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndShowPendingLocationRequest();
      _refreshOnResume();
    }
  }

  /// Self-heal the map/home screen on resume instead of relying on a manual
  /// pull-to-refresh. Backgrounding suspends the socket connection (mobile OSes
  /// don't keep the Dart isolate scheduled while backgrounded), so without this
  /// the screen keeps showing whatever location/status it last received before
  /// being backgrounded. Dispatching GetHomepageData(isSilentRefresh: true)
  /// both refetches current data AND re-runs _initSocketListeners (which fully
  /// recreates + reconnects the socket and rejoins the child room) — see
  /// HomepageBloc._onGetHomepageData / _initSocketListeners.
  void _refreshOnResume() {
    final now = DateTime.now();
    if (_lastResumeRefreshAt != null &&
        now.difference(_lastResumeRefreshAt!) < const Duration(seconds: 5)) {
      return; // Avoid redundant refreshes on rapid pause/resume flicker.
    }
    _lastResumeRefreshAt = now;
    injector<HomepageBloc>().add(const GetHomepageData(isSilentRefresh: true));
  }

  void _checkAndShowPendingLocationRequest() {
    AppLogger.info(
      '💡 _checkAndShowPendingLocationRequest check: mounted=$mounted, open=$_isLocationShareSheetOpen',
    );
    print(
      '💡 [FCM CHECK] _checkAndShowPendingLocationRequest check: mounted=$mounted, open=$_isLocationShareSheetOpen',
    );
    if (!mounted || _isLocationShareSheetOpen) return;
    final pendingJson = _sharedPrefsService.getString(
      'pending_location_share_request',
    );
    AppLogger.info('💡 pendingJson: $pendingJson');
    if (pendingJson != null && pendingJson.isNotEmpty) {
      try {
        final data = json.decode(pendingJson) as Map<String, dynamic>;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isLocationShareSheetOpen) {
            AppLogger.info('💡 Triggering approval sheet for data: $data');
            _showLocationShareApprovalSheet(data);
          }
        });
      } catch (e) {
        AppLogger.error('Failed to parse pending location request JSON: $e');
      }
    }
  }

  void _handleIncomingLocationShareAccepted(Map<String, dynamic> data) {
    AppLogger.info(
      '💡 _handleIncomingLocationShareAccepted called with data: $data',
    );
    print('💡 [FCM ACCEPTED] Handling accepted share request: $data');
    try {
      final String childId = data['child_id'] ?? 'mock_rohan';
      final String childName = data['child_name'] ?? 'Rohan';
      final double lat =
          double.tryParse(data['lat']?.toString() ?? '') ?? 12.9716;
      final double lng =
          double.tryParse(data['lng']?.toString() ?? '') ?? 77.5946;
      final String? expiresAtStr = data['expires_at'];
      final DateTime expiresAt = expiresAtStr != null
          ? DateTime.tryParse(expiresAtStr) ??
                DateTime.now().add(const Duration(minutes: 30))
          : DateTime.now().add(const Duration(minutes: 30));

      setState(() {
        _activeSharedChildData = {
          'child_id': childId,
          'child_name': childName,
          'avatar': data['avatar'] ?? 'Boy 03.png',
          'lat': lat,
          'lng': lng,
          'expires_at': expiresAt,
        };
        _viewingSharedChild = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$childName\'s shared location is now visible on your map',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      AppLogger.error('❌ Error handling location_share_accepted: $e');
    }
  }

  // helper to make import of min() safe
  int min(int a, int b) => a < b ? a : b;

  void _showRequestLocationSheet() {
    final TextEditingController phoneController = TextEditingController(
      text: "",
    );
    final TextEditingController notesController = TextEditingController();
    bool isLoadingRequest = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: 24 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF0C1D37),
                            size: 24,
                          ),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Phone Number',
                      style: GoogleFonts.poppins(
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.poppins(
                        fontSize: 15.0.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0C1D37),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Parent Mobile No',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF0C1D37),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Notes (Optional)',
                      style: GoogleFonts.poppins(
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      keyboardType: TextInputType.text,
                      style: GoogleFonts.poppins(
                        fontSize: 15.0.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0C1D37),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add notes for the parent...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF0C1D37),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF000000),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isLoadingRequest
                            ? null
                            : () async {
                                if (phoneController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter a phone number',
                                      ),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                  return;
                                }
                                setSheetState(() {
                                  isLoadingRequest = true;
                                });

                                final repo = injector<HomeRepository>();
                                final response = await repo
                                    .requestLocationSharing(
                                      phoneNumber: phoneController.text.trim(),
                                      notes:
                                          notesController.text.trim().isNotEmpty
                                          ? notesController.text.trim()
                                          : null,
                                    );

                                if (response.isSuccess) {
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Location request sent to ${phoneController.text.trim()} successfully!',
                                        ),
                                        backgroundColor: const Color(
                                          0xFF10B981,
                                        ),
                                      ),
                                    );
                                  }
                                } else {
                                  setSheetState(() {
                                    isLoadingRequest = false;
                                  });
                                  if (sheetContext.mounted) {
                                    ScaffoldMessenger.of(
                                      sheetContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to send request: ${response.message}',
                                        ),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: isLoadingRequest
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Request',
                                style: GoogleFonts.poppins(
                                  fontSize: 16.0.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTimeExtensionApprovalSheet(Map<String, dynamic> data) {
    if (_isTimeExtensionSheetOpen) return;

    final String requestId = data['request_id'] ?? '';
    final String childName = data['child_name'] ?? 'Your child';
    final String appName = data['app_name'] ?? 'this app';
    final String packageName = data['package_name'] ?? '';
    final int requestedMinutes =
        int.tryParse(data['requested_minutes']?.toString() ?? '') ?? 15;

    if (requestId.isEmpty) return;

    // Same heuristic AppLockBloc already uses to tell iOS opaque tokens
    // apart from Android package names, since the push doesn't carry a
    // platform field.
    final platform =
        packageName.startsWith('usage_cat_') ||
            packageName.startsWith('usage_app_')
        ? 'ios'
        : 'android';

    _isTimeExtensionSheetOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        bool isResponding = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> respond(bool approve) async {
              setSheetState(() => isResponding = true);
              final response = await injector<TimeLimitRepository>()
                  .resolveExtensionRequest(
                    requestId: requestId,
                    approve: approve,
                    platform: platform,
                  );
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      response.isSuccess
                          ? (approve
                                ? 'Extra time granted to $childName'
                                : 'Request denied')
                          : (response.message.isNotEmpty
                                ? response.message
                                : 'Something went wrong'),
                    ),
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 10,
                bottom: 24 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.hourglass_bottom_rounded,
                          color: Color(0xFF0066FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'More Time Request',
                        style: GoogleFonts.poppins(
                          fontSize: 18.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C1D37),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1EE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFFE5DE),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      '$childName wants $requestedMinutes more minutes on $appName.',
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isResponding ? null : () => respond(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Deny',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isResponding ? null : () => respond(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0066FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isResponding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Approve',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _isTimeExtensionSheetOpen = false;
    });
  }

  // Child-requests-logout approval sheet — cloned from
  // _showTimeExtensionApprovalSheet above (same request/resolve shape,
  // "wants to log out" instead of "wants more time"). No platform field
  // needed here since resolving a logout request never touches the native
  // app-lock layer.
  void _showLogoutApprovalSheet(Map<String, dynamic> data) {
    if (_isLogoutRequestSheetOpen) return;

    final String requestId = data['request_id'] ?? '';
    final String childName = data['child_name'] ?? 'Your child';
    if (requestId.isEmpty) return;

    _isLogoutRequestSheetOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        bool isResponding = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> respond(bool approve) async {
              setSheetState(() => isResponding = true);
              final response = await injector<LogoutRequestRepository>()
                  .resolveLogoutRequest(requestId: requestId, approve: approve);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      response.isSuccess
                          ? (approve
                                ? '$childName has been logged out'
                                : 'Logout request denied')
                          : (response.message.isNotEmpty
                                ? response.message
                                : 'Something went wrong'),
                    ),
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 10,
                bottom: 24 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFF0066FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Logout Request',
                        style: GoogleFonts.poppins(
                          fontSize: 18.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C1D37),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1EE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFFE5DE),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      '$childName wants to log out of the app.',
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isResponding ? null : () => respond(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Reject',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isResponding ? null : () => respond(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0066FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isResponding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Accept',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _isLogoutRequestSheetOpen = false;
    });
  }

  void _showLocationShareApprovalSheet(Map<String, dynamic> data) {
    AppLogger.info(
      '💡 _showLocationShareApprovalSheet called with data: $data',
    );
    print(
      '💡 [FCM SHEET] _showLocationShareApprovalSheet called with data: $data',
    );

    if (_isLocationShareSheetOpen) {
      AppLogger.warning(
        '⚠️ location share sheet is already open. Skipping duplicate show call.',
      );
      print(
        '⚠️ [FCM SHEET] location share sheet is already open. Skipping duplicate show call.',
      );
      return;
    }

    try {
      final String requesterName = data['requester_name'] ?? 'Parent A';
      final String? notes = data['notes'];
      final String requestId = data['request_id'] ?? 'dummy_id';

      List<ChildProfile> localChildren = _sharedPrefsService.getChildren();
      AppLogger.info('💡 Children count: ${localChildren.length}');
      if (localChildren.isEmpty) {
        localChildren = [
          ChildProfile(
            childId: 'mock_aisha',
            childCode: 'AI123',
            childName: 'Aisha',
            authToken: 'dummy',
            lastActiveAt: DateTime.now(),
          ),
          ChildProfile(
            childId: 'mock_rohan',
            childCode: 'RO123',
            childName: 'Rohan',
            authToken: 'dummy',
            lastActiveAt: DateTime.now(),
          ),
          ChildProfile(
            childId: 'mock_priya',
            childCode: 'PR123',
            childName: 'Priya',
            authToken: 'dummy',
            lastActiveAt: DateTime.now(),
          ),
        ];
      }

      final Map<String, String> childAges = {
        'Aisha': '8 yrs',
        'Rohan': '11 yrs',
        'Priya': '6 yrs',
      };

      String selectedDuration = '30 min';
      final List<String> selectedKids = [];

      if (localChildren.length >= 2) {
        selectedKids.add(localChildren[0].childId);
        selectedKids.add(localChildren[1].childId);
      } else if (localChildren.isNotEmpty) {
        selectedKids.add(localChildren[0].childId);
      }

      _isLocationShareSheetOpen = true;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          bool isResponding = false;
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 10,
                  bottom: 24 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEFF6FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFF0066FF),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Location Share',
                            style: GoogleFonts.poppins(
                              fontSize: 18.0.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0C1D37),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1EE),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFFE5DE),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFE5DE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFF97316),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$requesterName is requesting for your kids location',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.0.sp,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0C1D37),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Sent just now',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.0.sp,
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (notes != null &&
                                      notes.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFFFE5DE),
                                        ),
                                      ),
                                      child: Text(
                                        'Note: "$notes"',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.0.sp,
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEFF6FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.access_time_filled,
                              color: Color(0xFF0066FF),
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Share location for',
                            style: GoogleFonts.poppins(
                              fontSize: 14.0.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0C1D37),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            [
                              '15 min',
                              '30 min',
                              '1 hour',
                              '2 hours',
                              '6 hours',
                              '24 hours',
                            ].map((duration) {
                              final isSelected = selectedDuration == duration;
                              return GestureDetector(
                                onTap: isResponding
                                    ? null
                                    : () {
                                        setSheetState(() {
                                          selectedDuration = duration;
                                        });
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF0066FF)
                                        : Colors.white,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF0066FF)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    duration,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.0.sp,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF0C1D37),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select kids to share location',
                          style: GoogleFonts.poppins(
                            fontSize: 14.0.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: localChildren.map((kid) {
                          final isSelected = selectedKids.contains(kid.childId);
                          final name = kid.childName;
                          final displayAge = childAges[name] ?? '8 yrs';
                          String initials = name.length >= 2
                              ? name.substring(0, 2).toUpperCase()
                              : name.toUpperCase();
                          return Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: GestureDetector(
                              onTap: isResponding
                                  ? null
                                  : () {
                                      setSheetState(() {
                                        if (isSelected) {
                                          selectedKids.remove(kid.childId);
                                        } else {
                                          selectedKids.add(kid.childId);
                                        }
                                      });
                                    },
                              child: Column(
                                children: [
                                  Stack(
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: isSelected
                                              ? Border.all(
                                                  color: const Color(
                                                    0xFF0066FF,
                                                  ),
                                                  width: 2,
                                                )
                                              : null,
                                          color: isSelected
                                              ? const Color(0xFFEFF6FF)
                                              : const Color(0xFFECFDF5),
                                        ),
                                        alignment: Alignment.center,
                                        child:
                                            kid.avatar != null &&
                                                kid.avatar!.isNotEmpty
                                            ? CircleAvatar(
                                                radius: 30,
                                                backgroundImage:
                                                    (kid.avatar!.startsWith(
                                                          'http://',
                                                        ) ||
                                                        kid.avatar!.startsWith(
                                                          'https://',
                                                        ))
                                                    ? NetworkImage(kid.avatar!)
                                                    : AssetImage(
                                                            kid.avatar!
                                                                    .startsWith(
                                                                      'assets/',
                                                                    )
                                                                ? kid.avatar!
                                                                : 'assets/images/childavatar/${kid.avatar!}',
                                                          )
                                                          as ImageProvider,
                                              )
                                            : Text(
                                                initials,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16.0.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color: isSelected
                                                      ? const Color(0xFF0066FF)
                                                      : const Color(0xFF059669),
                                                ),
                                              ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            width: 20,
                                            height: 20,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF0066FF),
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    name,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.0.sp,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF0C1D37),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    displayAge,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.0.sp,
                                      color: const Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0066FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: selectedKids.isEmpty || isResponding
                              ? null
                              : () async {
                                  setSheetState(() {
                                    isResponding = true;
                                  });

                                  int durationMin = 30;
                                  if (selectedDuration.contains('15')) {
                                    durationMin = 15;
                                  } else if (selectedDuration.contains('30')) {
                                    durationMin = 30;
                                  } else if (selectedDuration.contains(
                                    '1 hour',
                                  )) {
                                    durationMin = 60;
                                  } else if (selectedDuration.contains(
                                    '2 hours',
                                  )) {
                                    durationMin = 120;
                                  } else if (selectedDuration.contains(
                                    '6 hours',
                                  )) {
                                    durationMin = 360;
                                  } else if (selectedDuration.contains(
                                    '24 hours',
                                  )) {
                                    durationMin = 1440;
                                  }

                                  final repo = injector<HomeRepository>();
                                  final response = await repo
                                      .respondToLocationRequest(
                                        requestId: requestId,
                                        action: 'accept',
                                        childIds: selectedKids,
                                        durationMinutes: durationMin,
                                      );

                                  if (response.isSuccess) {
                                    await SharedPrefsService.prefs.remove(
                                      'pending_location_share_request',
                                    );
                                    injector<FirebaseNotificationService>()
                                        .clearPendingLocationShareRequest();

                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }

                                    final List<String> sharedNames =
                                        localChildren
                                            .where(
                                              (k) => selectedKids.contains(
                                                k.childId,
                                              ),
                                            )
                                            .map((k) => k.childName)
                                            .toList();

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Accepted share request for: ${sharedNames.join(', ')}',
                                          ),
                                          backgroundColor: const Color(
                                            0xFF10B981,
                                          ),
                                        ),
                                      );
                                    }
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Accepted share request for: ${sharedNames.join(', ')}',
                                          ),
                                          backgroundColor: const Color(
                                            0xFF10B981,
                                          ),
                                        ),
                                      );
                                    }

                                    // Parent B is the sharing parent, so we do not show the shared child as an active incoming share on their own map.
                                    // The shared child is already visible as their own child on the home map.
                                    final activeOutgoingShares =
                                        SharedPrefsService.prefs.getStringList(
                                          'active_outgoing_shares',
                                        ) ??
                                        [];
                                    final newShareJson =
                                        '{"share_id":"share_${DateTime.now().millisecondsSinceEpoch}","recipient_phone":"+14987889999","child_id":"${selectedKids.first}","child_name":"${sharedNames.first}","expires_at":"${DateTime.now().add(const Duration(minutes: 30)).toIso8601String()}"}';
                                    activeOutgoingShares.add(newShareJson);
                                    await SharedPrefsService.prefs
                                        .setStringList(
                                          'active_outgoing_shares',
                                          activeOutgoingShares,
                                        );
                                  } else {
                                    setSheetState(() {
                                      isResponding = false;
                                    });
                                    if (sheetContext.mounted) {
                                      ScaffoldMessenger.of(
                                        sheetContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to accept request: ${response.message}',
                                          ),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: isResponding
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Accept Request',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16.0.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(
                              color: Color(0xFFDC2626),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: isResponding
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  _showRejectionReasonDialog(requestId);
                                },
                          child: Text(
                            'Reject Request',
                            style: GoogleFonts.poppins(
                              fontSize: 16.0.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Location will only be shared for the selected duration. You can revoke access anytime.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 11.0.sp,
                          color: const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ).whenComplete(() {
        _isLocationShareSheetOpen = false;
        AppLogger.info('💡 [FCM SHEET] Sheet closed/dismissed');
        print('💡 [FCM SHEET] Sheet closed/dismissed');
      });
    } catch (e, stack) {
      _isLocationShareSheetOpen = false;
      AppLogger.error('❌ Error in _showLocationShareApprovalSheet: $e');
    }
  }

  void _showRejectionReasonDialog(String requestId) {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isRejecting = false;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Reject Request',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0C1D37),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please specify the reason for rejection (optional):',
                    style: GoogleFonts.poppins(
                      fontSize: 13.0.sp,
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    enabled: !isRejecting,
                    decoration: InputDecoration(
                      hintText: 'e.g. Kids are sleeping, already home...',
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isRejecting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isRejecting
                      ? null
                      : () async {
                          setDialogState(() {
                            isRejecting = true;
                          });
                          final String reason = reasonController.text.trim();

                          final repo = injector<HomeRepository>();
                          final response = await repo.respondToLocationRequest(
                            requestId: requestId,
                            action: 'reject',
                            rejectionReason: reason.isNotEmpty ? reason : null,
                          );

                          if (response.isSuccess) {
                            await SharedPrefsService.prefs.remove(
                              'pending_location_share_request',
                            );
                            injector<FirebaseNotificationService>()
                                .clearPendingLocationShareRequest();

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    reason.isEmpty
                                        ? 'Request rejected'
                                        : 'Request rejected. Reason: "$reason"',
                                  ),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isRejecting = false;
                            });
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed to reject request: ${response.message}',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                  child: isRejecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Reject',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<BitmapDescriptor?> _loadCustomMarker(
    int batteryPercentage,
    String? avatar, {
    bool isOnline = true,
  }) async {
    try {
      Uint8List imageBytes;

      if (avatar != null &&
          (avatar.startsWith('http://') || avatar.startsWith('https://'))) {
        final response = await http.get(Uri.parse(avatar));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        } else {
          ByteData data = await rootBundle.load(
            'assets/images/childavatar/Boy 03.png',
          );
          imageBytes = data.buffer.asUint8List();
        }
      } else {
        String assetPath = 'assets/images/childavatar/Boy 03.png';
        if (avatar != null && avatar.isNotEmpty) {
          assetPath = 'assets/images/childavatar/$avatar';
        }
        try {
          ByteData data = await rootBundle.load(assetPath);
          imageBytes = data.buffer.asUint8List();
        } catch (e) {
          ByteData data = await rootBundle.load(
            'assets/images/childavatar/Boy 03.png',
          );
          imageBytes = data.buffer.asUint8List();
        }
      }

      ui.Codec codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 100,
        targetHeight: 100,
      );
      ui.FrameInfo fi = await codec.getNextFrame();
      final ui.Image avatarImage = fi.image;

      // Create a canvas to draw our custom pin marker
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      const double size = 130;
      const double radius = 50;
      const double pointerHeight = 20;
      const double pointerWidth = 16;

      final borderPaint = Paint()
        ..color = const Color(0xFF4ADE80)
        ..style = PaintingStyle.fill;

      final path = Path();
      path.moveTo(size / 2 - pointerWidth / 2, size - pointerHeight);
      path.lineTo(size / 2, size);
      path.lineTo(size / 2 + pointerWidth / 2, size - pointerHeight);
      path.close();
      canvas.drawPath(path, borderPaint);

      canvas.drawCircle(const Offset(size / 2, radius), radius, borderPaint);

      final bgPaint = Paint()
        ..color = const Color(0xFFF97316)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(size / 2, radius), radius - 6, bgPaint);

      final clipPath = Path()
        ..addOval(
          Rect.fromCircle(
            center: const Offset(size / 2, radius),
            radius: radius - 6,
          ),
        );
      canvas.save();
      canvas.clipPath(clipPath);

      canvas.drawImageRect(
        avatarImage,
        Rect.fromLTWH(
          0,
          0,
          avatarImage.width.toDouble(),
          avatarImage.height.toDouble(),
        ),
        Rect.fromCircle(
          center: const Offset(size / 2, radius),
          radius: radius - 6,
        ),
        Paint(),
      );
      canvas.restore();

      // Online/offline status dot — small badge at the top-right of the pin,
      // green when the child's device last reported active, grey otherwise.
      const double dotRadius = 12;
      final dotCenter = Offset(size / 2 + radius * 0.62, radius * 0.28);
      canvas.drawCircle(
        dotCenter,
        dotRadius + 3,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        dotCenter,
        dotRadius,
        Paint()
          ..color = isOnline
              ? const Color(0xFF22C55E)
              : const Color(0xFF9CA3AF),
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      return BitmapDescriptor.bytes(pngBytes!.buffer.asUint8List());
    } catch (e) {
      return null;
    }
  }

  /// Format address to hide plus codes (e.g. "F9FJ+GQF,") and the trailing
  /// country name, otherwise showing the FULL address (street, area, city,
  /// district, state, PIN code) — this card only falls back to this
  /// formatted address when the location does NOT match a saved place (see
  /// `matchingPlace`/`placeName` above, which shows just the place name in
  /// that case); when it does fall back, the user wants the complete
  /// address, not a truncated one — client explicitly asked to match a
  /// reference app's breakdown ("Kaverappa Layout, Vasanth Nagar, Bengaluru,
  /// Bangalore North, Bengaluru Urban, Karnataka, 560052, India") minus the
  /// country. Previously discarded everything past the 2nd comma-separated
  /// part (e.g. "Alanallur Puthur Nattukkal Road, Mannarkad, Palakkad" got
  /// cut down to just "Mannarkad, Kerala"-shape output); a later pass
  /// over-corrected by also dropping any bare-numeric segment, which took
  /// the PIN code out too when Google's reverse-geocode returned it as its
  /// own trailing comma segment (e.g. "..., Kerala, 683577") — the PIN code
  /// is exactly the kind of street-level-adjacent detail a parent wants,
  /// same reasoning as keeping the street name, so it stays like every
  /// other segment; only the country name is dropped, since the app is
  /// India-only and it adds nothing.
  String _formatAddress(String? address) {
    if (address == null) return '';
    final trimmed = address.trim();
    if (trimmed.isEmpty) return '';

    // Split by comma into parts
    final rawParts = trimmed.split(',');
    final parts = rawParts
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return trimmed;

    // Detect and skip leading plus code part like "F9FJ+GQF"
    final plusCodeRegex = RegExp(r'^[A-Z0-9+]{4,}$');
    int startIndex = 0;
    if (plusCodeRegex.hasMatch(parts.first)) {
      startIndex = 1;
    }

    if (startIndex >= parts.length) {
      return parts.last;
    }

    var kept = parts.sublist(startIndex);
    // Drop a trailing country-name segment (case-insensitive) — this app is
    // India-only, so "India" is the only value this will ever actually see,
    // but matching case-insensitively costs nothing and avoids a silent
    // miss if Google ever returns it capitalized differently.
    if (kept.isNotEmpty && kept.last.toLowerCase() == 'india') {
      kept = kept.sublist(0, kept.length - 1);
    }
    if (kept.isEmpty) return parts.last;

    return kept.join(', ');
  }

  String _formatSinceTime(String? sinceStr) {
    if (sinceStr == null || sinceStr.isEmpty) return 'Active';
    try {
      if (sinceStr.toLowerCase().contains('am') ||
          sinceStr.toLowerCase().contains('pm')) {
        final clean = sinceStr.replaceAll(' ', '').toLowerCase();
        if (clean.endsWith('am')) {
          return 'Since ${clean.replaceAll('am', ' AM')}';
        } else if (clean.endsWith('pm')) {
          return 'Since ${clean.replaceAll('pm', ' PM')}';
        }
        return 'Since $sinceStr';
      }

      final dateTime = DateTime.tryParse(sinceStr);
      if (dateTime != null) {
        // Relative "last active" wording so the parent can tell freshness at
        // a glance, instead of only a wall-clock time they'd have to compare
        // against the current time themselves.
        final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
        if (!diff.isNegative) {
          if (diff.inSeconds < 90) return 'Active now';
          if (diff.inMinutes < 60) {
            return 'Active ${diff.inMinutes} min ago';
          }
          if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
          if (diff.inDays == 1) return 'Active yesterday';
          if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
        }

        final localDateTime = dateTime.toLocal();
        final hour = localDateTime.hour;
        final minute = localDateTime.minute.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        final displayHourStr = displayHour.toString().padLeft(2, '0');
        return 'Since $displayHourStr:$minute $period';
      }
    } catch (e) {
      // ignore
    }
    return 'Since $sinceStr';
  }

  // "Since <wall-clock time>" for the active-state status pill — how long
  // the child has been at their CURRENT spot (when this dwell began), not
  // how fresh the last GPS ping is. Sourced from the server's
  // stationarySince (location.controller.js getStationarySince: walks
  // location history backward from the latest fix, stopping at the first
  // point more than 120m away — that boundary's timestamp is dwell start).
  // Always a literal clock time regardless of how long ago that was —
  // unlike _formatSinceTime's relative "X min ago" wording, which answers a
  // different question (freshness of the last ping, not arrival time).
  String _formatArrivalTime(DateTime? since) {
    if (since == null) return 'Active';
    final local = since.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return 'Since $displayHour:$minute $period';
  }

  // Relative dwell duration for the status pill — "how long has the child
  // been here", stated the same way the "Last moved Xh ago" line above it
  // already states it. Used to show a wall-clock arrival time instead
  // ("Since 6:54 PM"), which technically encodes the same information but
  // reads as inconsistent/confusing next to a sibling line already saying
  // "13h ago" for the exact same timestamp — a parent has to do the math
  // themselves to see the two numbers agree. Matching the relative format
  // removes that mental step. Used for the status pill regardless of
  // online/offline — "how long has the child been here" is the same
  // question whether the device is currently reachable or not, so it
  // shouldn't just say the bare word "Offline" with no sense of duration.
  String _formatDwellTime(DateTime? since) {
    if (since == null) return 'Active';
    final diff = DateTime.now().toUtc().difference(since.toUtc());
    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return 'Since ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Since ${diff.inHours}h';
    return 'Since ${diff.inDays}d';
  }

  // Sourced from trackingSnapshot.latestLocation.deviceTimestamp specifically
  // — the same authoritative timestamp uiDirective.displayState itself was
  // computed from server-side — rather than state.currentLocation.since
  // (driven by the separate REST/socket location stream, see
  // HomepageBloc._isNewerLocationUpdate). Keeping the visible "last updated"
  // time tied to the same source the status badge is computed from avoids
  // the two ever telling a parent a contradictory story. Shown regardless of
  // whether location is off, so a parent isn't left with zero freshness
  // information when the badge alone can't fully explain what's going on.
  //
  // Labeled "Location updated", not just "Last updated" — a tracker can
  // check in (battery/online ping) far more recently than it last sent an
  // actual GPS fix (e.g. stationary and power-saving, or weak signal).
  // Confirmed real case: deviceStatus.lastUpdated was 1.5 min old while
  // this location timestamp was 4+ hours old — the bare word "Last
  // updated" read as if the whole device had gone quiet for 4 hours, when
  // only its location had.
  String? _formatLastUpdated(DateTime? deviceTimestamp) {
    if (deviceTimestamp == null) return null;
    final diff = DateTime.now().toUtc().difference(deviceTimestamp.toUtc());
    if (diff.isNegative) return 'Location updated just now';
    if (diff.inSeconds < 90) return 'Location updated just now';
    if (diff.inMinutes < 60)
      return 'Location updated ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Location updated ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Location updated yesterday';
    if (diff.inDays < 7) return 'Location updated ${diff.inDays}d ago';
    return 'Location updated ${deviceTimestamp.toLocal().toString().split('.').first}';
  }

  // Readable text for a JT808 tracker alarm type (see naviQ-server
  // tcp/jt808.js's ALARM_BIT_NAMES) — the raw enum string isn't something
  // to show a parent directly.
  String _formatAlarmLabel(String? alarmType) {
    switch (alarmType) {
      case 'GEOFENCE':
        return 'Entry fence alarm';
      case 'EMERGENCY_SOS':
        return 'Emergency SOS alarm';
      case 'OVERSPEED':
        return 'Overspeed alarm';
      case 'MAIN_POWER_OFF':
        return 'Device power disconnected';
      case 'MAIN_POWER_UNDERVOLTAGE':
        return 'Device battery low';
      case 'GNSS_MODULE_FAULT':
        return 'GPS module fault';
      case 'VEHICLE_THEFT':
        return 'Theft alarm';
      default:
        return 'Device alarm';
    }
  }

  String _formatLastAlarmTime(DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().toUtc().difference(at.toUtc());
    if (diff.isNegative || diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  // Replaces the bare word "STALE" on the top status badge. A parent reading
  // "Stale" sees an alarm — something's wrong — when the actual situation is
  // just that the last known fix hasn't changed in a while (location itself
  // is still correct, see the "why does it say Stale when the location is
  // right" support conversation this was added for). Showing how long it's
  // been unchanged instead tells them what's actually true.
  //
  // Prefers latestLocation.stationarySince (server-computed "how long has
  // the child actually been at this exact spot", from location.controller.js
  // getStationarySince) over deviceTimestamp (only "how long since the last
  // GPS ping") — a phone parked in one place keeps checking in periodically,
  // so deviceTimestamp alone stays small even after a full day stationary
  // (confirmed against a real report: this app showed "25m" for a child a
  // competitor app correctly showed as "1d" unchanged). Falls back to
  // deviceTimestamp when stationarySince isn't available (e.g. an older
  // backend). Kept in the same short all-caps style as the sibling
  // ACTIVE NOW/OFFLINE words so the badge still reads as one design.
  String _staleBadgeWord(LatestLocation? location) {
    final anchor = location?.stationarySince ?? location?.deviceTimestamp;
    if (anchor == null) return 'UNCHANGED';
    final plus =
        location?.stationarySince != null &&
            location?.stationarySinceUncapped == false
        ? '+'
        : '';
    final diff = DateTime.now().toUtc().difference(anchor.toUtc());
    if (diff.isNegative || diff.inMinutes < 1) return '<1M AGO';
    if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';
    if (diff.inHours < 24) return '${diff.inHours}H$plus AGO';
    if (diff.inDays == 1) return '1D$plus AGO';
    return '${diff.inDays}D$plus AGO';
  }

  // Same replacement for the lower status pill's "Stale" label — framed as
  // "how long has this location held" rather than the alarming word.
  String _staleDurationPill(LatestLocation? location) {
    final anchor = location?.stationarySince ?? location?.deviceTimestamp;
    if (anchor == null) return 'Unchanged';
    final plus =
        location?.stationarySince != null &&
            location?.stationarySinceUncapped == false
        ? '+'
        : '';
    final diff = DateTime.now().toUtc().difference(anchor.toUtc());
    if (diff.isNegative || diff.inMinutes < 1) return 'Unchanged <1m';
    if (diff.inMinutes < 60) return 'Unchanged ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Unchanged ${diff.inHours}h$plus';
    if (diff.inDays == 1) return 'Unchanged 1d$plus';
    return 'Unchanged ${diff.inDays}d$plus';
  }

  // Label for the isDeviceUnreachable pill. "Location unavailable" used to
  // cover this case too, same wording/red styling as the genuine
  // isLocationOff (permission/GPS toggle) case — misleading, since a device
  // that simply hasn't phoned home (no network, app killed, iOS background
  // suspension, powered off) may have location fully working on the phone
  // itself. "Unreachable" + elapsed time says what's actually true.
  String _unreachableDurationPill(DateTime? deviceTimestamp) {
    if (deviceTimestamp == null) return 'Unreachable';
    final diff = DateTime.now().toUtc().difference(deviceTimestamp.toUtc());
    if (diff.isNegative || diff.inMinutes < 1) return 'Unreachable';
    if (diff.inMinutes < 60) return 'Unreachable ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Unreachable ${diff.inHours}h';
    if (diff.inDays == 1) return 'Unreachable 1d';
    return 'Unreachable ${diff.inDays}d';
  }

  // "Last moved" companion to _formatLastUpdated — consolidates the two
  // timestamps (last GPS ping vs. last time the child actually changed
  // location) into one line under the status badge instead of the moved-time
  // being buried inside the stale-only status pill further down the card.
  String? _formatLastMoved(LatestLocation? location) {
    final anchor = location?.stationarySince;
    if (anchor == null) return null;
    final diff = DateTime.now().toUtc().difference(anchor.toUtc());
    if (diff.isNegative || diff.inMinutes < 1) return 'Last moved just now';
    if (diff.inMinutes < 60) return 'Last moved ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last moved ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Last moved yesterday';
    return 'Last moved ${diff.inDays}d ago';
  }

  int _currentIndex = 0;
  // Bumped every time the Profile tab is tapped, so ProfileView (kept alive
  // inside the IndexedStack below, never disposed/recreated on tab switch —
  // see its own didUpdateWidget) can refresh its list on every visit, not
  // just once at cold-start/app-resume. Without this, backend-side status
  // fields (e.g. is_active) that changed since the tab was last built kept
  // showing stale until a manual pull-to-refresh happened to land on a
  // fresher moment — confirmed real complaint.
  int _profileRefreshToken = 0;

  Widget _buildBottomNavigationBar() {
    // Wrapped in SafeArea(bottom) — without it this Container sits flush
    // with the physical bottom edge on notch/gesture-nav devices, so the
    // iOS home-indicator bar draws directly on top of the Explore/Profile
    // labels instead of below them. SafeArea adds the missing bottom inset
    // (~34pt) so the nav bar's own content clears it.
    return SafeArea(
      top: false,
      child: Container(
        height: 76,
        // Flat, borderless — no shadow/elevation and no rounded top corners,
        // matching the flush reference nav bar instead of reading as a
        // separate floating card sitting on top of the page content.
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomNavItem(
              0,
              _currentIndex == 0 ? Icons.home_rounded : Icons.home_outlined,
              'Home',
            ),
            _buildBottomNavItem(
              1,
              _currentIndex == 1
                  ? Icons.settings_rounded
                  : Icons.settings_outlined,
              'Settings',
            ),
            _buildBottomNavItem(2, Icons.menu_rounded, 'Explore'),
            _buildBottomNavItem(
              3,
              _currentIndex == 3
                  ? Icons.person_rounded
                  : Icons.person_outline_rounded,
              'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
          if (index == 3) _profileRefreshToken++;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0x003DB5E9), Color(0x2E2352BB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
            ),
            child: Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF0C1D37)
                  : const Color(0xFF94A3B8),
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11.0.sp,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected
                  ? const Color(0xFF0C1D37)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: injector<HomepageBloc>(),
      child: BlocListener<HomepageBloc, HomepageState>(
        listenWhen: (prev, curr) {
          if (curr is HomepageSuccess) {
            final activeId = _sharedPrefsService.getString('child_id');
            if (prev is HomepageSuccess) {
              return prev.isLoading != curr.isLoading ||
                  activeId != _currentLoadedChildId;
            }
            return true;
          }
          return false;
        },
        listener: (context, state) {
          if (state is HomepageSuccess) {
            if (!state.isLoading) {
              _finishRefreshProgress();
            }
            final activeId = _sharedPrefsService.getString('child_id');
            if (activeId != null && activeId != _currentLoadedChildId) {
              _currentLoadedChildId = activeId;
              _loadSavedPlaces();
              final now = DateTime.now();
              final todayStr =
                  "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
              context.read<GeofenceBloc>().add(
                GetGeofencesRequested(childId: activeId, date: todayStr),
              );
            }
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTabContent(context),
              const SettingsView(),
              ExploreView(
                onNavigateToHome: () {
                  setState(() {
                    _currentIndex = 0;
                  });
                },
              ),
              ProfileView(
                refreshToken: _profileRefreshToken,
                onNavigateToHome: () {
                  setState(() {
                    _currentIndex = 0;
                  });
                },
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomNavigationBar(),
        ),
      ),
    );
  }

  Widget _buildHomeTabContent(BuildContext context) {
    return BlocBuilder<HomepageBloc, HomepageState>(
      builder: (context, state) {
        if (state is HomepageError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: ${state.message}',
                    style: AppTextStyles.body1.copyWith(color: AppColors.error),
                  ),
                  const SizedBox(height: AppSizes.spacingM),
                  CommonButton(
                    text: 'Retry',
                    onPressed: () {
                      injector<HomepageBloc>().add(GetHomepageData());
                    },
                  ),
                ],
              ),
            ),
          );
        }

        if (state is! HomepageSuccess) {
          return const SizedBox.shrink();
        }

        if (state.hasNoChild) {
          return _buildNoChildConnectedUI(context);
        }

        // Same NEVER_SHARED check the location card above already uses —
        // Scroll/Geo Guard/Route Map/Screentime all read data that simply
        // doesn't exist yet for a child whose device has never checked in,
        // so leaving them tappable and normal-looking invites a parent to
        // read "0 Apps Locked" / "0 Fencing" as real state instead of
        // "nothing reported yet". Greying + disabling them here matches the
        // "device isn't paired yet" card above instead of contradicting it.
        final isChildNotPaired =
            !_viewingSharedChild &&
            state.trackingSnapshot?.uiDirective.displayState == 'NEVER_SHARED';
        final childName =
            _sharedPrefsService.getString('child_name') ?? 'Ananya';
        // Backend already resolves place_name authoritatively (Child.currentPlace,
        // kept in sync by the geofence pipelines — see location.controller.js /
        // geofence.service.js) — trust it first instead of re-deriving a match
        // client-side. _findMatchingPlace's own box-match against _savedPlaces
        // is a separately-fetched, per-child-switch list that can be stale or
        // momentarily empty (e.g. right after switching children), which used
        // to silently fall through to a client-side reverse-geocoded raw
        // street address even while the backend already knew the correct
        // place name (confirmed real case: backend said "House", this still
        // showed "LIG Phase-III, BDA Apartment-Kaniminike, ..."). Only fall
        // back to the client-side match/address when the backend genuinely
        // has no place name for this location.
        final backendPlaceName = state.currentLocation?.placeName;
        final hasBackendPlaceName =
            backendPlaceName != null &&
            backendPlaceName.isNotEmpty &&
            backendPlaceName != 'Unknown';
        final matchingPlace = hasBackendPlaceName
            ? null
            : _findMatchingPlace(
                state.currentLocation?.lat,
                state.currentLocation?.lng,
              );
        final placeName = hasBackendPlaceName
            ? backendPlaceName
            : (matchingPlace != null
                  ? matchingPlace.name
                  : (state.currentLocation?.address != null
                        ? _formatAddress(state.currentLocation?.address)
                        : 'Unknown Place'));

        final double screenHeight = MediaQuery.of(context).size.height;
        // The map is pinned behind the scroll content (reference behaviour:
        // the sheet slides up OVER a fixed map). Its full painted height is
        // half the screen, but the pinned header only reserves the part above
        // the location card — the card (its own sliver) overlaps the rest.
        const double kLocationCardOverlap = 195;
        final double mapFullHeight = screenHeight * 0.5;
        final double mapHeaderExtent = mapFullHeight - kLocationCardOverlap;

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // _isUserDraggingScroll used to drive the map's AnimatedContainer
            // duration. The map no longer animates its height, and this
            // setState rebuilt the ENTIRE Home page at the start and end of
            // every drag — a visible hitch exactly when the sheet is grabbed.
            /*
            final draggingNow =
                notification is ScrollStartNotification ||
                notification is ScrollUpdateNotification;
            if (draggingNow != _isUserDraggingScroll) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _isUserDraggingScroll = draggingNow);
                }
              });
            }
            */
            return false;
          },
          child: LayoutBuilder(
            builder: (context, box) {
              final double layoutHeight = box.maxHeight;
              final double topInset = MediaQuery.of(context).padding.top;
              // Sheet rests with its top at the location card (map visible
              // above it) and can be dragged up to just under the status bar.
              final double restSheet =
                  ((layoutHeight - mapHeaderExtent) / layoutHeight).clamp(
                    0.3,
                    1.0,
                  );
              final double maxSheet = ((layoutHeight - topInset) / layoutHeight)
                  .clamp(restSheet, 1.0);
              // Dragging down lowers the sheet until the map fills ~75% of
              // the screen (only the card header peeks above the nav bar).
              const double kMapExpandedFraction = 0.75;
              final double minSheet =
                  (1.0 - (screenHeight * kMapExpandedFraction) / layoutHeight)
                      .clamp(0.1, restSheet);
              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  // Map is only washed out when the sheet is raised ABOVE its
                  // resting spot; lowering it just reveals more map.
                  final range = n.maxExtent - restSheet;
                  _mapFadeAmount.value = range <= 0
                      ? 0.0
                      : ((n.extent - restSheet) / range).clamp(0.0, 1.0);
                  return false;
                },
                child: Stack(
                  children: [
                    // Fixed map behind the sheet.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: layoutHeight,
                      child: Stack(
                        children: [
                          // Layer 1: Map Background with rounded bottom corners
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(36),
                                bottomRight: Radius.circular(36),
                              ),
                              child: RepaintBoundary(
                                child: _HomeMapBackground(
                                  key: _mapBackgroundKey,
                                  // Visible map (above the resting sheet) is the
                                  // top half; pad the rest so the marker/camera
                                  // centre lands in it, not behind the sheet.
                                  mapPadding: EdgeInsets.only(
                                    bottom: layoutHeight - mapFullHeight,
                                  ),
                                  loadCustomMarker: _loadCustomMarker,
                                  activeSharedChildData: _activeSharedChildData,
                                  viewingSharedChild: _viewingSharedChild,
                                  ownChildLocation:
                                      state.currentLocation != null
                                      ? LatLng(
                                          state.currentLocation!.lat,
                                          state.currentLocation!.lng,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),

                          // Layer 1.2: wash the map out to white as the parent
                          // scrolls the cards up over it (Figma/reference
                          // behaviour). Ignores pointers so map gestures and the
                          // overlays above it are unaffected.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _mapFadeAmount,
                                builder: (context, fade, _) => fade <= 0.01
                                    ? const SizedBox.shrink()
                                    : ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(36),
                                          bottomRight: Radius.circular(36),
                                        ),
                                        child: ColoredBox(
                                          color: Colors.white.withValues(
                                            alpha: 0.92 * fade,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),

                          // Layer 1.4: "Updating location..." overlay while a
                          // fresh fetch is in flight (e.g. right after switching
                          // the selected child). homepage_bloc.dart already
                          // clears currentLocation on a child switch so the OLD
                          // child's marker doesn't flash before the new one loads
                          // — but with nothing shown in its place, that gap read
                          // as unexplained/confusing (reported live: briefly
                          // shows the old child's spot, then jumps 1-2s later).
                          // This makes the gap legible instead of silent.
                          if (state.isLoading)
                            Positioned(
                              top: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Updating location…',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.5.sp,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          // Layer 1.5: Floating Overlay Avatar for Shared Kid
                          () {
                            final floatingChildren =
                                state.sharedChildren.isNotEmpty
                                ? state.sharedChildren
                                : (_activeSharedChildData != null
                                      ? [
                                          SharedChild(
                                            shareId:
                                                _activeSharedChildData!['child_id'],
                                            childId:
                                                _activeSharedChildData!['child_id'],
                                            childName:
                                                _activeSharedChildData!['child_name'],
                                            latitude:
                                                _activeSharedChildData!['lat'],
                                            longitude:
                                                _activeSharedChildData!['lng'],
                                            batteryPercentage:
                                                _activeSharedChildData!['battery_percentage'] ??
                                                50,
                                            avatar:
                                                _activeSharedChildData!['avatar'],
                                            expiresAt:
                                                _activeSharedChildData!['expires_at'],
                                            lastSyncAt:
                                                _activeSharedChildData!['last_sync_at'],
                                          ),
                                        ]
                                      : <SharedChild>[]);

                            if (floatingChildren.isEmpty)
                              return const SizedBox.shrink();

                            return Positioned(
                              top: 80,
                              right: 16,
                              child: Column(
                                children: floatingChildren.map((child) {
                                  final isSelected =
                                      _viewingSharedChild &&
                                      _activeSharedChildData != null &&
                                      _activeSharedChildData!['child_id'] ==
                                          child.childId;
                                  final hasAvatar =
                                      child.avatar != null &&
                                      child.avatar!.isNotEmpty;
                                  final String initials = child.childName
                                      .substring(
                                        0,
                                        min(2, child.childName.length),
                                      )
                                      .toUpperCase();

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 12.0,
                                    ),
                                    child: Column(
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _activeSharedChildData = {
                                                'child_id': child.childId,
                                                'child_name': child.childName,
                                                'avatar':
                                                    child.avatar ??
                                                    'Boy 03.png',
                                                'lat': child.latitude,
                                                'lng': child.longitude,
                                                'expires_at': child.expiresAt,
                                                'battery_percentage':
                                                    child.batteryPercentage,
                                                'last_sync_at':
                                                    child.lastSyncAt,
                                              };
                                              _viewingSharedChild = true;
                                            });
                                          },
                                          child: Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                              border: Border.all(
                                                color: isSelected
                                                    ? const Color(0xFF0066FF)
                                                    : const Color(0xFFCBD5E1),
                                                width: 2.5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.15),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                if (hasAvatar)
                                                  ClipOval(
                                                    child: Image(
                                                      image:
                                                          (child.avatar!
                                                                  .startsWith(
                                                                    'http://',
                                                                  ) ||
                                                              child.avatar!
                                                                  .startsWith(
                                                                    'https://',
                                                                  ))
                                                          ? NetworkImage(
                                                              child.avatar!,
                                                            )
                                                          : AssetImage(
                                                                  child.avatar!
                                                                          .startsWith(
                                                                            'assets/',
                                                                          )
                                                                      ? child
                                                                            .avatar!
                                                                      : 'assets/images/childavatar/${child.avatar!}',
                                                                )
                                                                as ImageProvider,
                                                      width: 50,
                                                      height: 50,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) {
                                                            return Text(
                                                              initials,
                                                              style: GoogleFonts.poppins(
                                                                fontSize:
                                                                    14.0.sp,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    const Color(
                                                                      0xFF0066FF,
                                                                    ),
                                                              ),
                                                            );
                                                          },
                                                    ),
                                                  )
                                                else
                                                  Text(
                                                    initials,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14.0.sp,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: const Color(
                                                        0xFF0066FF,
                                                      ),
                                                    ),
                                                  ),
                                                Positioned(
                                                  top: 0,
                                                  right: 0,
                                                  child: Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF10B981,
                                                      ),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.05,
                                                ),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: Text(
                                            child.childName,
                                            style: GoogleFonts.poppins(
                                              fontSize: 10.0.sp,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0C1D37),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          }(),

                          // Layer 1.6: Overlay banner if viewing shared child
                          if (_viewingSharedChild &&
                              _activeSharedChildData != null)
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.share_location,
                                          color: Color(0xFF0066FF),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Viewing: ${_activeSharedChildData!['child_name']} (Shared)',
                                              style: GoogleFonts.poppins(
                                                fontSize: 13.0.sp,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF0C1D37),
                                              ),
                                            ),
                                            Text(
                                              _getRemainingTimeText(
                                                _activeSharedChildData!['expires_at'],
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 11.0.sp,
                                                color: const Color(0xFF64748B),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFF1F5F9,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _viewingSharedChild = false;
                                        });
                                      },
                                      child: Text(
                                        'Switch to Home',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.0.sp,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Layer FAB: floating "Map" FAB visible only when collapsed (20% height)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            bottom: (_mapHeightFraction == 0.20) ? 96 : -60,
                            right: 16,
                            child: AnimatedOpacity(
                              opacity: (_mapHeightFraction == 0.20) ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _mapHeightFraction = 0.50;
                                  });
                                  if (_homeScrollController.hasClients) {
                                    _homeScrollController.animateTo(
                                      0,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOutCubic,
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0066FF),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.map_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Map',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14.0.sp,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Layer FAB: Locate Me button
                          Positioned(
                            top: mapHeaderExtent - 60,
                            right: 16,
                            child: GestureDetector(
                              onTap: () {
                                final target =
                                    _viewingSharedChild &&
                                        _activeSharedChildData != null
                                    ? LatLng(
                                        _activeSharedChildData!['lat'],
                                        _activeSharedChildData!['lng'],
                                      )
                                    : (state.currentLocation != null
                                          ? LatLng(
                                              state.currentLocation!.lat,
                                              state.currentLocation!.lng,
                                            )
                                          : null);
                                if (target != null) {
                                  _mapBackgroundKey.currentState?._animateTo(
                                    target,
                                    zoom: 15.0,
                                  );
                                }
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.my_location_rounded,
                                  color: Color(0xFF0C1D37),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Draggable sheet: slivers inside scroll once the sheet is
                    // fully expanded; before that, dragging lifts the sheet
                    // over the map (which fades to white).
                    Positioned.fill(
                      child: DraggableScrollableSheet(
                        initialChildSize: restSheet,
                        minChildSize: minSheet,
                        maxChildSize: maxSheet,
                        snap: true,
                        snapSizes: [restSheet],
                        builder: (context, scrollController) => CustomScrollView(
                          controller: scrollController,
                          physics: const ClampingScrollPhysics(),
                          slivers: [
                            // Sliver 1: location card — top of the sheet, floats over the map.
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  20,
                                ),
                                child: _buildLocationCardOnly(
                                  context,
                                  _viewingSharedChild &&
                                          _activeSharedChildData != null
                                      ? _activeSharedChildData!['child_name']
                                      : childName,
                                  _viewingSharedChild &&
                                          _activeSharedChildData != null
                                      ? 'Shared Location'
                                      : placeName,
                                  state,
                                ),
                              ),
                            ),

                            // Sliver 2: Scrollable content cards below the map
                            if (!_viewingSharedChild)
                              DecoratedSliver(
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF8FAFC),
                                ),
                                sliver: SliverPadding(
                                  padding: const EdgeInsets.all(16.0),
                                  sliver: SliverList(
                                    delegate: SliverChildListDelegate([
                                      // Live Trip Status Card — shown only when actively
                                      // travelling. Hidden per request (kept here, not
                                      // deleted, so it's a one-line flip back to `true`).
                                      if (false)
                                        _LiveTripCard(
                                          activeTrip: state.activeTrip,
                                          isDeviceOffline: _isDeviceOffline(
                                            state,
                                          ),
                                        ),

                                      // 2. Scroll & Geo Guard Feature Cards — greyed out and
                                      // disabled until the child's device is actually paired
                                      // (see isChildNotPaired above).
                                      IgnorePointer(
                                        ignoring: isChildNotPaired,
                                        child: Opacity(
                                          opacity: isChildNotPaired
                                              ? 0.45
                                              : 1.0,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _buildFeatureCard(
                                                  title: 'Scroll',
                                                  subtitle:
                                                      'Social Media & Apps',
                                                  statusText:
                                                      state
                                                          .features
                                                          ?.scrollStatusText ??
                                                      '0 Apps Locked',
                                                  icon:
                                                      Icons.smartphone_rounded,
                                                  cardBg: const Color(
                                                    0xFFEFF6FF,
                                                  ),
                                                  borderCol: const Color(
                                                    0xFFDBEAFE,
                                                  ),
                                                  iconCol: const Color(
                                                    0xFF3B82F6,
                                                  ),
                                                  statusBg: const Color(
                                                    0xFFDBEAFE,
                                                  ),
                                                  statusTextCol: const Color(
                                                    0xFF1D4ED8,
                                                  ),
                                                  onTap: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            const SocialAppsView(),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: _buildFeatureCard(
                                                  title: 'Geo Guard',
                                                  subtitle:
                                                      'Places & Geofencing',
                                                  statusText:
                                                      state
                                                          .features
                                                          ?.geoGuardStatusText ??
                                                      '0 Fencing',
                                                  icon: Icons
                                                      .location_on_outlined,
                                                  cardBg: const Color(
                                                    0xFFFFF7ED,
                                                  ),
                                                  borderCol: const Color(
                                                    0xFFFFEDD5,
                                                  ),
                                                  iconCol: const Color(
                                                    0xFFF97316,
                                                  ),
                                                  statusBg: const Color(
                                                    0xFFFFEDD5,
                                                  ),
                                                  statusTextCol: const Color(
                                                    0xFFC2410C,
                                                  ),
                                                  onTap: () {
                                                    final childId =
                                                        _sharedPrefsService
                                                            .getString(
                                                              'child_id',
                                                            );
                                                    final parentId =
                                                        _sharedPrefsService
                                                            .getString(
                                                              'parent_id',
                                                            );
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            GeoFencingView(
                                                              childId: childId,
                                                              parentId:
                                                                  parentId,
                                                            ),
                                                      ),
                                                    ).then((_) {
                                                      injector<HomepageBloc>().add(
                                                        const GetHomepageData(),
                                                      );
                                                      _loadSavedPlaces();
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // 3. Today's Route Map Card — same disabled treatment.
                                      IgnorePointer(
                                        ignoring: isChildNotPaired,
                                        child: Opacity(
                                          opacity: isChildNotPaired
                                              ? 0.45
                                              : 1.0,
                                          child: _buildRouteMapCard(context),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // 4. Upgrade to Pro Banner
                                      _buildUpgradeProBanner(),
                                      const SizedBox(height: 24),

                                      // 5. Screentime Today Section — same disabled treatment.
                                      IgnorePointer(
                                        ignoring: isChildNotPaired,
                                        child: Opacity(
                                          opacity: isChildNotPaired
                                              ? 0.45
                                              : 1.0,
                                          child: _buildScreentimeSection(
                                            context,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),

                                      // 6. Shortcuts Section
                                      _buildShortcutsSection(context),
                                      const SizedBox(height: 24),

                                      // 7. Help Centre Section
                                      _buildHelpCentreSection(context),
                                    ]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Single shared source for "is this device's tracking currently offline"
  // so the location card badge, its status pill, and the live-trip badge
  // all agree with each other and with the map banner — instead of each
  // deriving its own contradictory signal from a different data source.
  bool _isDeviceOffline(HomepageSuccess state) {
    if (_viewingSharedChild) return false;
    final uiDirective = state.trackingSnapshot?.uiDirective;
    if (uiDirective == null) return false;
    final displayState = uiDirective.displayState;
    final isLocationOff =
        displayState == 'PERMISSION_DENIED' || displayState == 'GPS_DISABLED';
    return !isLocationOff && !uiDirective.showLiveMarker;
  }

  Widget _buildLocationCardOnly(
    BuildContext context,
    String childName,
    String placeName,
    HomepageSuccess state,
  ) {
    // A genuine child switch resets HomepageSuccess to .initial() while the
    // new child's fetch is in flight (homepage_bloc.dart _onGetHomepageData)
    // — currentLocation only comes back null for that reset, never for an
    // ordinary same-child silent refresh. The map already shows an
    // "Updating location..." pill for this window, but that pill sits
    // inside the map layer and scrolls out of view once the map is
    // collapsed — this card was still rendering the outgoing child's
    // name/place/pills underneath with nothing to say they were stale,
    // which is exactly what parents reported reading as "showing the wrong
    // child's data" after switching from Profile/Settings. Show a plain
    // loading state here too so it stays visible regardless of scroll
    // position.
    if (!_viewingSharedChild &&
        state.isLoading &&
        state.currentLocation == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C1D37).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF0066FF),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "Loading $childName's location…",
              style: GoogleFonts.poppins(
                fontSize: 13.0.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    // A freshly-added/logged-in child that has never once posted a location
    // fix (or device status) yet — the backend flags this explicitly as
    // NEVER_SHARED (location.controller.js getChildTrackingSnapshot) rather
    // than leaving latest_location null and letting displayState default to
    // LIVE. Before this check, that fell through to the normal card below
    // with an empty/"Unknown Place" address and a pill that lied "Active" —
    // there's nothing active about a device that has never checked in once.
    // The moment the child's device actually posts its first location, this
    // snapshot naturally flips to LIVE on the next poll/refresh and the
    // normal card renders itself — no extra wiring needed here beyond not
    // showing a false "connected" state in the meantime.
    if (!_viewingSharedChild &&
        state.trackingSnapshot?.uiDirective.displayState == 'NEVER_SHARED') {
      final childCode = _sharedPrefsService.getString('child_code');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C1D37).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFB45309),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$childName's device isn't paired yet",
                        style: GoogleFonts.poppins(
                          fontSize: 15.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C1D37),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'GPS tracking, screen time rules, and safe geofencing '
                        'will activate automatically once the companion app is paired.',
                        style: GoogleFonts.poppins(
                          fontSize: 12.0.sp,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: childCode == null
                    ? null
                    : () => Share.share(
                        "Set up $childName on NaviQ: install the NaviQ app on "
                        "${childName}'s phone and enter this code to connect — $childCode",
                      ),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(
                  'Share Invite Link',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Location is "off" only when GPS/location-services is actually disabled
    // or permission was revoked — NOT merely whenever showLiveMarker is false
    // (that also goes false for STALE/UNREACHABLE, which is normal for an
    // idle/backgrounded phone, not a location toggle).
    //
    // This used to re-derive that distinction locally from the raw
    // gpsStatus/permissionStatus strings instead of the server's own
    // uiDirective.displayState — which meant every server-side refinement to
    // how PERMISSION_DENIED gets decided (e.g. discounting a stale denied
    // flag when real location data is actually flowing) had to be
    // separately re-applied here too, and one instance was found where it
    // hadn't been: a device with denied_forever stuck in deviceStatus but
    // confirmed-working location still showed "LOCATION OFF" on this card
    // even after the map banner was already fixed. displayState is the
    // single place PERMISSION_DENIED/GPS_DISABLED actually get decided now
    // (see location.controller.js getChildTrackingSnapshot) — checking it
    // directly means this card automatically inherits every future
    // correction there instead of needing its own parallel fix each time.
    // Shared children don't carry a tracking snapshot, so always treat as
    // active.
    final trackingSnapshot = state.trackingSnapshot;
    final displayState = trackingSnapshot?.uiDirective.displayState;
    final isLocationOff =
        !_viewingSharedChild &&
        (displayState == 'PERMISSION_DENIED' || displayState == 'GPS_DISABLED');
    // The device itself is unreachable (no internet / powered off / hasn't
    // phoned home in a while) — distinct from isLocationOff, which is a
    // permission/GPS toggle problem. OFFLINE/UNREACHABLE are the backend's
    // own, already-discounted verdicts (getChildTrackingSnapshot only sets
    // these after ruling out a merely-stale isOnline flag or transient
    // network blip via hasFreshLocationEvidence — see location.controller.js),
    // so trusting displayState here directly is safe. Before this check, a
    // genuinely-unreachable device with no stationarySince to compute (no
    // recent history to derive "how long here" from) fell through to
    // _formatDwellTime's null-case default of "Active" — exactly backwards,
    // since there's nothing active about a device we can't reach.
    final isDeviceUnreachable =
        !_viewingSharedChild &&
        (displayState == 'OFFLINE' || displayState == 'UNREACHABLE');
    // Kid hasn't moved from the last known spot — device not phoning home
    // right now doesn't mean the location itself is in doubt, it just means
    // no new fix has come in. Showing plain dwell time ("11h" in the normal
    // neutral pill) instead of a red "Unreachable" alert tells the parent
    // what actually matters (child has been at this spot this whole time)
    // without implying something's broken. Only escalate to the alert
    // when there's truly no stationarySince to anchor a duration on (no
    // location history at all to say "how long here").
    final showUnreachableAlert =
        isDeviceUnreachable &&
        trackingSnapshot?.latestLocation?.stationarySince == null;
    // Distinct from isLocationOff: the device/GPS toggle is fine, but the
    // backend itself says this isn't live data right now (OFFLINE,
    // UNREACHABLE, STALE, ...). Reusing showLiveMarker rather than listing
    // displayState strings here means this inherits the backend's own
    // freshness judgement call (e.g. BACKGROUND_RESTRICTED only counts as
    // non-live once it's actually stale) instead of a second, possibly
    // out-of-sync copy of that logic living here too.
    // _isDeviceOffline(state) only means "not live right now" (server
    // show_live_marker: false) — true for both a genuinely unreachable
    // device AND a device that's ONLINE but whose last location fix went
    // stale. Both cases share the same amber pill/color, but the *word*
    // shown must not say "OFFLINE" for the latter — that contradicts the
    // server's own device_status: ONLINE (and the sibling live-trip badge,
    // which already says "STALE" for the identical condition).
    // NOTE: this pill used to suppress to "ACTIVE NOW" whenever the last
    // known fix sat at a known place (placeName known/non-"unknown"),
    // matching the banner's calm-at-home behavior further down this file.
    // But that made this pill lie outright — a device that's actually
    // UNREACHABLE/OFFLINE for hours still showed green "ACTIVE NOW" here,
    // directly contradicting the "Last updated Xh ago" text rendered right
    // below it on the same card. The banner (silent) and this status pill
    // (honest OFFLINE/STALE) are different UI: staying silent is fine, but a
    // pill that explicitly claims "ACTIVE NOW" must not do so when the
    // device isn't. Always reflect the real showLiveMarker signal here — a
    // known place only softens the map banner, not this pill's own honesty.

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C1D37).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Kid's name — on the same line as the action icons, matching
              // the Figma card header (name left, icons right). "is at
              // <place>" now renders as its own line underneath instead of
              // being joined into this same text block.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        childName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 18.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C1D37),
                        ),
                      ),
                    ),
                    // Data-source badge — tells the parent this location
                    // came from the linked physical GPS tracker, not the
                    // child's phone. Only ever shown when a tracker is
                    // actually linked (device_imei set); confirmed real
                    // case this was ambiguous to a parent otherwise.
                    if (!_viewingSharedChild &&
                        state.deviceInfo?.deviceImei != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.gps_fixed_rounded,
                              size: 10,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'GPS Tracker',
                              style: GoogleFonts.poppins(
                                fontSize: 9.0.sp,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: _isRefreshing
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              value: _refreshProgress / 100,
                              strokeWidth: 2,
                              color: const Color(0xFF10B981),
                              backgroundColor: const Color(0xFFE2E8F0),
                            ),
                          ),
                          Text(
                            '$_refreshProgress',
                            style: GoogleFonts.poppins(
                              fontSize: 10.0.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0C1D37),
                            ),
                          ),
                        ],
                      )
                    : IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.refresh,
                          size: 16,
                          color: Color(0xFF0C1D37),
                        ),
                        onPressed: _startRefreshProgress,
                      ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    size: 16,
                    color: Color(0xFF0C1D37),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.share_outlined,
                    size: 16,
                    color: Color(0xFF0C1D37),
                  ),
                  onPressed: () async {
                    final lat =
                        _viewingSharedChild && _activeSharedChildData != null
                        ? _activeSharedChildData!['lat'] as double?
                        : state.currentLocation?.lat;
                    final lng =
                        _viewingSharedChild && _activeSharedChildData != null
                        ? _activeSharedChildData!['lng'] as double?
                        : state.currentLocation?.lng;
                    // Both store links so whoever receives this (parent or
                    // not already on NaviQ) can download it regardless of
                    // which platform they're on — a share text can't detect
                    // the recipient's device, so both are included labeled.
                    const appDownloadLines =
                        'Get NaviQ:\niOS: https://apps.apple.com/app/id6761759873\n'
                        'Android: https://play.google.com/store/apps/details?id=com.truenyx.naviqandroid';
                    // placeName (outer scope) is the raw backend/match
                    // value, which can be one of the "Unknown" sentinels —
                    // the card on screen never shows that bare word because
                    // _DynamicLocationText resolves it client-side via
                    // reverse geocoding before displaying it (same fix as
                    // the "Unknown Place"/"Unknown Address" leaks fixed
                    // earlier). The share text was bypassing that resolved
                    // value entirely, confirmed real case: card showed a
                    // real street address while Share's own preview showed
                    // literally "device is at Unknown". Resolve the same
                    // way here before sharing.
                    String shareLocationLabel = placeName;
                    const unresolvedSentinels = {
                      'Unknown',
                      'Unknown Location',
                      'Shared Location',
                      'Unknown Place',
                    };
                    if (unresolvedSentinels.contains(placeName) &&
                        lat != null &&
                        lng != null) {
                      try {
                        final placemarks = await placemarkFromCoordinates(
                          lat,
                          lng,
                        );
                        if (placemarks.isNotEmpty) {
                          final p = placemarks.first;
                          final resolved = [
                            p.street,
                            p.subLocality,
                            p.locality,
                            p.administrativeArea,
                          ].where((e) => e != null && e.isNotEmpty).join(', ');
                          if (resolved.isNotEmpty)
                            shareLocationLabel = resolved;
                        }
                      } catch (_) {
                        // Keep the raw placeName fallback — a failed lookup
                        // shouldn't block sharing entirely.
                      }
                    }
                    if (lat != null && lng != null) {
                      // Google's universal maps link — opens the native
                      // Google Maps app when installed, otherwise falls
                      // back to Google Maps in the browser. Works the same
                      // on iOS and Android, unlike a bare geo: URI.
                      final mapsLink =
                          'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                      Share.share(
                        '$childName is at $shareLocationLabel\n$mapsLink\n\n$appDownloadLines',
                      );
                    } else {
                      Share.share(
                        '$childName is at $shareLocationLabel\n\n$appDownloadLines',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DynamicLocationText(
            key: ValueKey(childName),
            childName: childName,
            initialPlaceName: placeName,
            position: _viewingSharedChild && _activeSharedChildData != null
                ? LatLng(
                    _activeSharedChildData!['lat'] ?? 0.0,
                    _activeSharedChildData!['lng'] ?? 0.0,
                  )
                : LatLng(
                    state.currentLocation?.lat ?? 0.0,
                    state.currentLocation?.lng ?? 0.0,
                  ),
          ),
          // "Last updated" — moved below the name+address block per request,
          // instead of sitting above it next to the icon row. "Last moved"
          // used to sit alongside it but was dropped — the status pill's
          // "Since Xh" already says the same dwell duration, so the two side
          // by side was the exact same number said twice.
          if (!_viewingSharedChild &&
              _formatLastUpdated(
                    trackingSnapshot?.latestLocation?.deviceTimestamp,
                  ) !=
                  null) ...[
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final locTs = trackingSnapshot?.latestLocation?.deviceTimestamp;
                final locStaleMinutes = locTs == null
                    ? 0
                    : DateTime.now()
                          .toUtc()
                          .difference(locTs.toUtc())
                          .inMinutes;
                // Reassures the parent that the device itself is fine when
                // ONLY its location fix is stale — a tracker reports a
                // battery/online ping independently of a GPS fix (power
                // saving while stationary, or weak signal indoors), so
                // "device gone quiet" and "location hasn't refreshed" are
                // different facts the parent shouldn't have to infer.
                final showDeviceOnlineNote =
                    state.deviceInfo?.deviceImei != null &&
                    state.deviceInfo?.isOnline == true &&
                    locStaleMinutes > 15;
                return Text(
                  showDeviceOnlineNote
                      ? '${_formatLastUpdated(locTs)!} • Device online'
                      : _formatLastUpdated(locTs)!,
                  style: GoogleFonts.poppins(
                    fontSize: 11.0.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF94A3B8),
                  ),
                );
              },
            ),
          ],
          // Physical tracker alarm banner (GEOFENCE/MAIN_POWER_OFF/etc —
          // see naviQ-server tcp/jt808.js's ALARM_BIT_NAMES). Only ever
          // populated for a JT808 tracker, never a phone. Capped at 24h old
          // so a one-off alarm from yesterday doesn't sit here forever.
          if (!_viewingSharedChild &&
              state.deviceInfo?.lastAlarmType != null &&
              state.deviceInfo?.lastAlarmAt != null &&
              DateTime.now()
                      .toUtc()
                      .difference(state.deviceInfo!.lastAlarmAt!.toUtc())
                      .inHours <
                  24) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFF92400E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_formatAlarmLabel(state.deviceInfo!.lastAlarmType)} • ${_formatLastAlarmTime(state.deviceInfo!.lastAlarmAt)}',
                      style: GoogleFonts.poppins(
                        fontSize: 11.0.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Horizontally scrollable instead of a fixed spaceAround Row —
          // a 4th pill (altitude, tracker-only) plus a 5th (alarm context)
          // down the line no longer has to fit a fixed card width; it was
          // overflowing by 12px on a real tracker-linked child the moment
          // the altitude pill had something to show (confirmed real case).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildLocationStatusPill(
                  isLocationOff
                      ? Icons.location_off_rounded
                      : (showUnreachableAlert
                            ? Icons.wifi_off_rounded
                            : Icons.access_time_rounded),
                  isLocationOff
                      ? 'Location off'
                      : (showUnreachableAlert
                            ? _unreachableDurationPill(
                                trackingSnapshot
                                    ?.latestLocation
                                    ?.deviceTimestamp,
                              )
                            : (_viewingSharedChild &&
                                      _activeSharedChildData != null
                                  ? _formatSinceTime(
                                      _activeSharedChildData!['last_sync_at']
                                          ?.toString(),
                                    )
                                  : _formatDwellTime(
                                      trackingSnapshot
                                          ?.latestLocation
                                          ?.stationarySince,
                                    ))),
                  backgroundColor: isLocationOff || showUnreachableAlert
                      ? const Color(0xFFFEE2E2)
                      : const Color(0xFFEEF0F5),
                  contentColor: isLocationOff || showUnreachableAlert
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF323C56),
                ),
                const SizedBox(width: 8),
                _buildLocationStatusPill(
                  _viewingSharedChild && _activeSharedChildData != null
                      ? Icons.battery_std_rounded
                      : (state.deviceInfo?.isCharging == true
                            ? Icons.battery_charging_full_rounded
                            : Icons.battery_std_rounded),
                  _viewingSharedChild && _activeSharedChildData != null
                      ? '${_activeSharedChildData!['battery_percentage'] ?? 0}%'
                      : '${state.deviceInfo?.batteryPercentage ?? 0}%',
                ),
                if (!_viewingSharedChild) ...[
                  const SizedBox(width: 8),
                  _buildLocationStatusPill(
                    state.deviceInfo?.soundProfile.toLowerCase() == 'silent'
                        ? Icons.volume_off_rounded
                        : (state.deviceInfo?.soundProfile.toLowerCase() ==
                                  'vibrate'
                              ? Icons.vibration_rounded
                              : Icons.volume_up_rounded),
                    state.deviceInfo?.soundProfile ?? 'Vibrate',
                  ),
                ],
                // Altitude — only present for a physical JT808 tracker
                // (naviQ-server tcp/server.js), never a phone, so this pill
                // simply doesn't render for a phone-only child.
                if (!_viewingSharedChild &&
                    state.deviceInfo?.altitude != null) ...[
                  const SizedBox(width: 8),
                  _buildLocationStatusPill(
                    Icons.terrain_rounded,
                    '${state.deviceInfo!.altitude!.round()}m',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationStatusPill(
    IconData icon,
    String text, {
    Color? backgroundColor,
    Color? contentColor,
  }) {
    final bg = backgroundColor ?? const Color(0xFFF1F5F9);
    final content = contentColor ?? const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: content),
          const SizedBox(width: 4),
          Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 12.0.sp,
              fontWeight: FontWeight.bold,
              color: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String subtitle,
    required String statusText,
    required IconData icon,
    required Color cardBg,
    required Color borderCol,
    required Color iconCol,
    required Color statusBg,
    required Color statusTextCol,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderCol, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0C1D37).withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Circular background accent decoration matching Figma/Mockup
              Positioned(
                right: -25,
                top: -25,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cardBg,
                  ),
                ),
              ),

              // Main content column
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconCol, size: 22),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 18.0.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12.0.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusText,
                        style: GoogleFonts.poppins(
                          fontSize: 11.0.sp,
                          fontWeight: FontWeight.w800,
                          color: statusTextCol,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteMapCard(BuildContext context) {
    return BlocBuilder<HomepageBloc, HomepageState>(
      builder: (context, state) {
        final successState = state is HomepageSuccess ? state : null;
        final routeData = successState?.todayRoute;
        final distance = routeData != null
            ? '${routeData.totalDistanceKm} km'
            : '0.0 km';
        final newLoc = routeData != null
            ? '${routeData.newLocationsCount.toString().padLeft(2, '0')} new location${routeData.newLocationsCount == 1 ? '' : 's'}'
            : '00 new locations';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0C1D37).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Route Map",
                        style: GoogleFonts.poppins(
                          fontSize: 15.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C1D37),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$distance  •  $newLoc',
                        style: GoogleFonts.poppins(
                          fontSize: 11.0.sp,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(
                        context,
                      ).pushNamed(RouteNames.childLocationDetail);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0066FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildTimelineRow(routeData?.timeline),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimelineRow(List<TimelineNode>? nodes) {
    if (nodes == null || nodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            "No route activity recorded today",
            style: GoogleFonts.poppins(
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }

    final List<TimelineNode> listNodes = nodes;

    int latestActiveIndex = -1;
    for (int i = 0; i < listNodes.length; i++) {
      if (listNodes[i].isActive) {
        latestActiveIndex = i;
      }
    }

    final List<Widget> children = [];

    // Left Tail (matches color of first node)
    // Extended _kNodeDeadSpace into the first node's box on the right side
    // only — see _buildTimelineConnector for why this is needed: each node
    // is a 76-wide box with its 22-wide circle centered in it, so the 27px
    // either side of the circle renders nothing at all. Without this, the
    // tail visibly stopped short of the first circle instead of touching it.
    final bool firstActive = listNodes.isNotEmpty && listNodes[0].isActive;
    children.add(
      Padding(
        padding: const EdgeInsets.only(
          top: 9.5,
        ), // (22 circle height / 2) - (3 line height / 2) = 11 - 1.5 = 9.5
        child: SizedBox(
          width: 12,
          height: 3,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: 12 + _kNodeDeadSpace,
            minWidth: 0,
            child: Container(
              width: 12 + _kNodeDeadSpace,
              height: 3,
              color: firstActive
                  ? const Color(0xFF0066FF)
                  : const Color(0xFFE2E8F0),
            ),
          ),
        ),
      ),
    );

    // Nodes and connectors
    for (int i = 0; i < listNodes.length; i++) {
      final node = listNodes[i];
      final isHighlighted = (i == latestActiveIndex);

      children.add(
        _buildTimelineNode(
          label: node.label,
          time: node.time,
          isActive: node.isActive,
          isHighlighted: isHighlighted,
        ),
      );

      if (i < listNodes.length - 1) {
        final nextNode = listNodes[i + 1];
        final bool connectorActive = node.isActive && nextNode.isActive;
        children.add(_buildTimelineConnector(connectorActive));
      }
    }

    // Right Tail (matches color of last node) — extended into the last
    // node's box on the left side, matching the left tail above.
    final bool lastActive = listNodes.isNotEmpty && listNodes.last.isActive;
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 9.5),
        child: SizedBox(
          width: 12,
          height: 3,
          child: OverflowBox(
            alignment: Alignment.centerRight,
            maxWidth: 12 + _kNodeDeadSpace,
            minWidth: 0,
            child: Container(
              width: 12 + _kNodeDeadSpace,
              height: 3,
              color: lastActive
                  ? const Color(0xFF0066FF)
                  : const Color(0xFFE2E8F0),
            ),
          ),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      // Was an unbounded, non-scrollable Row rendering every stop in the
      // route unconditionally — with more than a handful of stops the
      // Expanded connectors squeezed the whole thing illegibly instead of
      // staying a compact stepper. Now horizontally scrollable so it stays
      // a fixed-size, swipeable stepper no matter how many stops there are.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildTimelineNode({
    required String label,
    required String time,
    required bool isActive,
    required bool isHighlighted,
  }) {
    // Fixed width so ~3-4 stops stay visible in the scrollable stepper's
    // viewport at once, with long labels ellipsizing instead of forcing
    // every node wider (which used to squeeze the whole unscrollable row).
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF0066FF) : Colors.white,
              shape: BoxShape.circle,
              border: isActive
                  ? null
                  : Border.all(color: const Color(0xFFE2E8F0), width: 2),
            ),
            child: isActive
                ? Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 12.0.sp,
              fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
              color: isHighlighted
                  ? const Color(0xFF0066FF)
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            time.isNotEmpty ? time : ' ',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 10.0.sp,
              fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
              color: isHighlighted
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  // Each timeline node is a 76-wide box (see _buildTimelineNode) so its
  // 22-wide circle can stay centered under a wider text label — which
  // leaves (76-22)/2 = 27px of empty space on either side of the circle
  // that nothing was drawing into. The connector/tail lines only spanned
  // their own slot, so they visibly stopped short of the circles instead
  // of touching them (confirmed live: a clear gap on both sides of every
  // stop). Every tail/connector now renders _kNodeDeadSpace wider than its
  // layout slot, via matching negative padding, so it visually reaches the
  // circle's edge without changing the Row's actual layout width/scroll
  // extent (the negative padding cancels the extra width back out for
  // layout purposes — only the paint/hit-test area grows).
  static const double _kNodeDeadSpace = 27.0;

  Widget _buildTimelineConnector(bool isActive) {
    // Fixed width, not Expanded — the row now lives inside a horizontal
    // SingleChildScrollView (see _buildTimelineRow), which gives its
    // children unbounded width; an Expanded/flex child there throws
    // ("RenderFlex children have non-zero flex but incoming width
    // constraints are unbounded").
    return Padding(
      padding: const EdgeInsets.only(top: 9.5),
      child: SizedBox(
        width: 32,
        height: 3,
        child: OverflowBox(
          maxWidth: 32 + _kNodeDeadSpace * 2,
          minWidth: 0,
          child: Container(
            width: 32 + _kNodeDeadSpace * 2,
            height: 3,
            color: isActive ? const Color(0xFF0066FF) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
    );
  }

  Widget _buildUpgradeProBanner() {
    // Was a bare Container — no GestureDetector/InkWell/onTap anywhere, so
    // the trailing arrow icon implied navigation that never actually
    // happened. Wrapped in InkWell (via Material, for the ripple to render
    // over the gradient) to open the same subscription sheet the global
    // upgrade banner uses elsewhere in the app.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => SubscriptionPopup.show(context, SubscriptionTier.basic),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Upgrade to Pro",
                    style: GoogleFonts.poppins(
                      fontSize: 15.0.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "Unlock all premium features",
                    style: GoogleFonts.poppins(
                      fontSize: 11.5.sp,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreentimeSection(BuildContext context) {
    return BlocBuilder<HomepageBloc, HomepageState>(
      builder: (context, state) {
        final successState = state is HomepageSuccess ? state : null;
        final screentimeData = successState?.screentimeToday;
        final totalText =
            screentimeData != null &&
                screentimeData.formattedTotalTime.isNotEmpty
            ? '${screentimeData.formattedTotalTime} total screen time'
            : '0.0 hrs total screen time';
        final limitText =
            screentimeData != null && screentimeData.limitMessage.isNotEmpty
            ? screentimeData.limitMessage
            : 'Within the daily limit';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Screentime Today",
              style: GoogleFonts.poppins(
                fontSize: 20.0.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0C1D37),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C1D37).withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildAppUsagesGrid(screentimeData?.appUsages),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              totalText,
                              style: GoogleFonts.poppins(
                                fontSize: 13.0.sp,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E40AF),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              limitText,
                              style: GoogleFonts.poppins(
                                fontSize: 10.5.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(
                                  0xFF1E40AF,
                                ).withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SocialAppsView(),
                              ),
                            );
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0xFF0066FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAppUsagesGrid(List<AppUsage>? appUsages) {
    if (appUsages == null || appUsages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insights_rounded,
              size: 48,
              color: const Color(0xFF94A3B8).withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              "No App Activity Today",
              style: GoogleFonts.poppins(
                fontSize: 14.5.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Screen time usage will be displayed here.",
              style: GoogleFonts.poppins(
                fontSize: 11.5.sp,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      );
    }

    final displayUsages = appUsages.take(6).toList();
    final List<Widget> rows = [];
    for (int i = 0; i < displayUsages.length; i += 2) {
      final item1 = displayUsages[i];
      final hasItem2 = i + 1 < displayUsages.length;
      final item2 = hasItem2 ? displayUsages[i + 1] : null;

      rows.add(
        Row(
          children: [
            Expanded(child: _buildDynamicAppTimeItem(item1)),
            if (item2 != null) ...[
              const SizedBox(width: 12),
              Expanded(child: _buildDynamicAppTimeItem(item2)),
            ] else ...[
              const Spacer(),
            ],
          ],
        ),
      );

      if (i + 2 < displayUsages.length) {
        rows.add(const SizedBox(height: 16));
      }
    }

    return Column(children: rows);
  }

  Widget _buildDynamicAppTimeItem(AppUsage item) {
    final Color brandColor = Color(
      int.tryParse(item.brandColor.replaceFirst('#', '0xFF')) ?? 0xFF0066FF,
    );

    Widget iconWidget;
    if (item.appIcon.startsWith('http')) {
      iconWidget = Image.network(
        item.appIcon,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.apps_rounded, color: brandColor, size: 18);
        },
      );
    } else if (item.appIcon.isNotEmpty) {
      final isPng =
          item.appIcon.endsWith('.png') ||
          item.appIcon.contains('YouTube') ||
          item.appIcon.contains('Instagram') ||
          item.appIcon.contains('WhatsApp');
      final finalPath = isPng
          ? item.appIcon.replaceAll('.svg', '.png')
          : item.appIcon;
      iconWidget = isPng
          ? Image.asset(
              finalPath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.apps_rounded, color: brandColor, size: 18);
              },
            )
          : SvgPicture.asset(
              finalPath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.apps_rounded, color: brandColor, size: 18);
              },
            );
    } else {
      iconWidget = Icon(
        item.appName.toLowerCase() == 'telegram'
            ? Icons.telegram
            : Icons.send_rounded,
        color: brandColor,
        size: 18,
      );
    }

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: brandColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: iconWidget,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0C1D37),
                ),
              ),
              Text(
                item.usageDuration,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Shortcuts",
          style: GoogleFonts.poppins(
            fontSize: 20.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildShortcutItem(
              'Screen Time',
              Icons.lock_outline_rounded,
              const Color(0xFFFFF1F2),
              const Color(0xFFF43F5E),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SocialAppsView()),
                );
              },
            ),
            _buildShortcutItem(
              'Request Location',
              Icons.monitor_heart,
              const Color(0xFFECFDF5),
              const Color(0xFF10B981),
              onTap: () {
                _showRequestLocationSheet();
              },
            ),
            _buildShortcutItem(
              'Notifications',
              Icons.notifications_outlined,
              const Color(0xFFFFF7ED),
              const Color(0xFFF97316),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationPage()),
                );
              },
            ),
            _buildShortcutItem(
              'Device',
              Icons.smartphone_outlined,
              const Color(0xFFFFF1F2),
              const Color(0xFFE11D48),
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const DevicesView()));
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShortcutItem(
    String label,
    IconData icon,
    Color bg,
    Color iconCol, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 74,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconCol, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: GoogleFonts.poppins(
                fontSize: 10.0.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF64748B),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpCentreSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Help Centre",
          style: GoogleFonts.poppins(
            fontSize: 20.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0C1D37).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHelpCentreItem(
                Icons.play_circle_outline_rounded,
                const Color(0xFFEFF6FF),
                const Color(0xFF2563EB),
                'Watch Quick Tutorial',
                'Quick answers to common questions',
              ),
              Container(
                height: 1,
                color: const Color(0xFFF1F5F9),
                margin: const EdgeInsets.symmetric(horizontal: 18),
              ),
              _buildHelpCentreItem(
                Icons.chat_bubble_outline_rounded,
                const Color(0xFFECFDF5),
                const Color(0xFF10B981),
                'Contact Support',
                'Chat with our team',
                onTap: () {
                  if (!SubscriptionFeatureGate.helpChannels().chat) {
                    UpgradeRestrictionDialog.showHelpChannelBlocked(
                      context,
                      'Chat',
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(
                        value: injector<ChatBloc>(),
                        child: const ChatScreen(
                          recipientId:
                              '65b2a3f7e1b2c3d4e5f67890', // Placeholder Admin ID
                          recipientName: 'NaviQ Support',
                        ),
                      ),
                    ),
                  );
                },
              ),
              Container(
                height: 1,
                color: const Color(0xFFF1F5F9),
                margin: const EdgeInsets.symmetric(horizontal: 18),
              ),
              _buildHelpCentreItem(
                Icons.shield_outlined,
                const Color(0xFFFFF7ED),
                const Color(0xFFF97316),
                'Safety Tips',
                'Best practices for family safety',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHelpCentreItem(
    IconData icon,
    Color bg,
    Color iconCol,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconCol, size: 18),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 13.5.sp,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0C1D37),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.poppins(
          fontSize: 11.0.sp,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF94A3B8),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFFCBD5E1),
      ),
      onTap: onTap,
    );
  }

  Widget _buildNoChildConnectedUI(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.paddingL),
      child: Column(
        children: [
          const Icon(Icons.child_care, size: 60, color: Colors.grey),
          Text("No Child Connected", style: AppTextStyles.headline3),
          const SizedBox(height: 20),
          CommonButton(
            text: "Add Child",
            onPressed: () => Navigator.of(context).pushNamed('/add-child'),
          ),
        ],
      ),
    );
  }
}

class _HomeMapBackground extends StatefulWidget {
  final Future<BitmapDescriptor?> Function(int, String?, {bool isOnline})
  loadCustomMarker;
  final Map<String, dynamic>? activeSharedChildData;
  final bool viewingSharedChild;
  final LatLng? ownChildLocation;
  final EdgeInsets mapPadding;

  const _HomeMapBackground({
    super.key,
    this.mapPadding = EdgeInsets.zero,
    required this.loadCustomMarker,
    required this.activeSharedChildData,
    required this.viewingSharedChild,
    this.ownChildLocation,
  });

  @override
  State<_HomeMapBackground> createState() => _HomeMapBackgroundState();
}

class _HomeMapBackgroundState extends State<_HomeMapBackground>
    with AutomaticKeepAliveClientMixin {
  BitmapDescriptor? _cachedMarkerIcon;
  int? _cachedBatteryPercentage;
  String? _cachedAvatar;
  bool? _cachedIsOnline;
  GoogleMapController? _mapController;
  bool _isFirstLocationAfterLoad = true;

  final Map<String, BitmapDescriptor> _cachedSharedMarkers = {};
  final Set<String> _loadingSharedMarkers = {};

  @override
  bool get wantKeepAlive => true; // preserve map state when scrolled off

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _HomeMapBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewingSharedChild != widget.viewingSharedChild ||
        oldWidget.activeSharedChildData != widget.activeSharedChildData) {
      if (_mapController != null) {
        if (widget.viewingSharedChild && widget.activeSharedChildData != null) {
          final target = LatLng(
            widget.activeSharedChildData!['lat'],
            widget.activeSharedChildData!['lng'],
          );
          _animateTo(target);
        } else if (!widget.viewingSharedChild &&
            widget.ownChildLocation != null) {
          _animateTo(widget.ownChildLocation!);
        }
      }
    }
  }

  Future<void> _loadMarkerIcon(
    int batteryPercentage,
    String? avatar, {
    bool isOnline = true,
  }) async {
    if (_cachedMarkerIcon != null &&
        _cachedBatteryPercentage == batteryPercentage &&
        _cachedAvatar == avatar &&
        _cachedIsOnline == isOnline) {
      return;
    }
    final icon = await widget.loadCustomMarker(
      batteryPercentage,
      avatar,
      isOnline: isOnline,
    );
    if (!mounted) return;
    setState(() {
      _cachedMarkerIcon = icon;
      _cachedBatteryPercentage = batteryPercentage;
      _cachedAvatar = avatar;
      _cachedIsOnline = isOnline;
    });
  }

  Future<void> _loadSharedMarkerIcon(
    String childId,
    int batteryPercentage,
    String? avatar,
  ) async {
    if (_cachedSharedMarkers.containsKey(childId) ||
        _loadingSharedMarkers.contains(childId)) {
      return;
    }
    _loadingSharedMarkers.add(childId);
    final icon = await widget.loadCustomMarker(batteryPercentage, avatar);
    _loadingSharedMarkers.remove(childId);
    if (!mounted) return;
    if (icon != null) {
      setState(() {
        _cachedSharedMarkers[childId] = icon;
      });
    }
  }

  Future<void> _animateTo(LatLng target, {double? zoom}) async {
    if (_mapController == null) return;

    AppLogger.info("Moving camera to $target");
    try {
      final currentZoom = zoom ?? await _mapController!.getZoomLevel();
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, currentZoom),
      );
    } catch (e) {
      AppLogger.debug('MapController animateCamera error: $e');
      // Do not nullify controller on a minor animation error to allow future updates
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return BlocListener<HomepageBloc, HomepageState>(
      listenWhen: (prev, curr) {
        if (prev is HomepageSuccess && curr is HomepageSuccess) {
          final locChanged =
              prev.currentLocation?.lat != curr.currentLocation?.lat ||
              prev.currentLocation?.lng != curr.currentLocation?.lng;
          final batteryChanged =
              prev.deviceInfo?.batteryPercentage !=
              curr.deviceInfo?.batteryPercentage;
          final onlineChanged =
              prev.deviceInfo?.isOnline != curr.deviceInfo?.isOnline;
          return locChanged || batteryChanged || onlineChanged;
        }
        return prev.runtimeType != curr.runtimeType;
      },
      listener: (context, state) {
        if (state is HomepageSuccess && state.isLoading) {
          _isFirstLocationAfterLoad = true;
        } else if (state is HomepageSuccess && state.currentLocation != null) {
          final loc = LatLng(
            state.currentLocation!.lat,
            state.currentLocation!.lng,
          );

          // Load marker icon first
          final battery = state.deviceInfo?.batteryPercentage ?? 0;
          final avatar = state.childAvatar;
          final isOnline = state.deviceInfo?.isOnline ?? true;
          _loadMarkerIcon(battery, avatar, isOnline: isOnline);

          // Animate to location on updates
          if (_mapController != null && !widget.viewingSharedChild) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted &&
                  _mapController != null &&
                  !widget.viewingSharedChild) {
                _animateTo(loc, zoom: _isFirstLocationAfterLoad ? 15.0 : null);
                _isFirstLocationAfterLoad = false;
              }
            });
          }
        }
      },
      child: BlocBuilder<HomepageBloc, HomepageState>(
        buildWhen: (prev, curr) {
          // Always rebuild when state type changes
          if (prev.runtimeType != curr.runtimeType) {
            return true;
          }

          // For HomepageSuccess states, rebuild if location or battery changed
          if (prev is HomepageSuccess && curr is HomepageSuccess) {
            final locChanged =
                prev.currentLocation?.lat != curr.currentLocation?.lat ||
                prev.currentLocation?.lng != curr.currentLocation?.lng;
            final batteryChanged =
                prev.deviceInfo?.batteryPercentage !=
                curr.deviceInfo?.batteryPercentage;
            final onlineChanged =
                prev.deviceInfo?.isOnline != curr.deviceInfo?.isOnline;
            return locChanged || batteryChanged || onlineChanged;
          }

          return false;
        },
        builder: (context, state) {
          final battery = state is HomepageSuccess && state.deviceInfo != null
              ? state.deviceInfo!.batteryPercentage
              : 0;
          final location =
              state is HomepageSuccess && state.currentLocation != null
              ? LatLng(state.currentLocation!.lat, state.currentLocation!.lng)
              : null;
          // Fire-and-forget load; widget will update when ready
          final avatar = state is HomepageSuccess ? state.childAvatar : null;
          final isOnline = state is HomepageSuccess
              ? (state.deviceInfo?.isOnline ?? true)
              : true;
          _loadMarkerIcon(battery, avatar, isOnline: isOnline);

          if (state is HomepageSuccess) {
            for (final child in state.sharedChildren) {
              _loadSharedMarkerIcon(
                child.childId,
                child.batteryPercentage,
                child.avatar,
              );
            }
          }

          final markers = <Marker>{
            if (location != null) ...{
              if (_cachedMarkerIcon != null)
                Marker(
                  markerId: const MarkerId('child_location'),
                  position: location,
                  icon: _cachedMarkerIcon!,
                  anchor: const Offset(0.5, 1.0),
                )
              else
                Marker(
                  markerId: const MarkerId('child_location'),
                  position: location,
                ),
            },
            if (state is HomepageSuccess) ...{
              for (final child in state.sharedChildren) ...{
                Marker(
                  markerId: MarkerId(child.childId),
                  position: LatLng(child.latitude, child.longitude),
                  icon:
                      _cachedSharedMarkers[child.childId] ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange,
                      ),
                  infoWindow: InfoWindow(
                    title: child.childName,
                    snippet:
                        'Battery: ${child.batteryPercentage}%${child.expiresAt != null ? " • Expires: ${TimeOfDay.fromDateTime(child.expiresAt!.toLocal()).format(context)}" : ""}',
                  ),
                ),
              },
            },
            if (widget.activeSharedChildData != null) ...{
              Marker(
                markerId: MarkerId(widget.activeSharedChildData!['child_id']),
                position: LatLng(
                  widget.activeSharedChildData!['lat'],
                  widget.activeSharedChildData!['lng'],
                ),
                infoWindow: InfoWindow(
                  title: widget.activeSharedChildData!['child_name'],
                  snippet: 'Shared Location',
                ),
              ),
            },
          };

          return Stack(
            children: [
              MapViewWidget(
                key: const ValueKey('home_map_static'),
                mapPadding: widget.mapPadding,
                width: double.infinity,
                height: double.infinity,
                interactive: true,
                useEagerGestures: true,
                currentPosition:
                    widget.viewingSharedChild &&
                        widget.activeSharedChildData != null
                    ? LatLng(
                        widget.activeSharedChildData!['lat'],
                        widget.activeSharedChildData!['lng'],
                      )
                    : location,
                markers: markers.toList(),
                // Parent's own position has no use on this map — only the
                // child's location matters here, and this flag is what
                // triggers the native OS location-permission prompt (Google
                // Maps SDK behavior, not something this app requests
                // itself), so a parent got asked for location access right
                // at login for a blue dot nothing on this screen reads.
                myLocationEnabled: false,
                minZoom: 0.0,
                maxZoom: 20,
                myLocationButtonEnabled:
                    false, // replaced by our custom Locate Me FAB
                onMapCreated: (controller) {
                  _mapController = controller;
                  final target =
                      widget.viewingSharedChild &&
                          widget.activeSharedChildData != null
                      ? LatLng(
                          widget.activeSharedChildData!['lat'],
                          widget.activeSharedChildData!['lng'],
                        )
                      : location;
                  if (target != null) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted && _mapController != null) {
                        _animateTo(target);
                      }
                    });
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController = null;
    super.dispose();
  }
}

class _DynamicLocationText extends StatefulWidget {
  final String childName;
  final String initialPlaceName;
  final LatLng position;

  const _DynamicLocationText({
    super.key,
    required this.childName,
    required this.initialPlaceName,
    required this.position,
  });

  @override
  State<_DynamicLocationText> createState() => _DynamicLocationTextState();
}

class _DynamicLocationTextState extends State<_DynamicLocationText> {
  String? _resolvedAddress;

  @override
  void initState() {
    super.initState();
    _resolveAddressIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _DynamicLocationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlaceName != widget.initialPlaceName ||
        oldWidget.position != widget.position) {
      _resolvedAddress = null;
      _resolveAddressIfNeeded();
    }
  }

  void _resolveAddressIfNeeded() {
    // 'Unknown Place' is _findMatchingPlace's own fallback text (home_page.dart)
    // for "not inside any saved geofence, and no backend/client address to show
    // yet" — a different literal string from the backend's "Unknown" default,
    // so it silently fell through this check and rendered as the dead label
    // "is at Unknown Place" instead of resolving a real address the same way
    // the other no-name cases already do. Confirmed real case: a genuinely
    // fresh location (4 min old, outside any saved place) showed "Unknown
    // Place" while the child had clearly moved.
    if (widget.initialPlaceName == 'Unknown Location' ||
        widget.initialPlaceName == 'Unknown' ||
        widget.initialPlaceName == 'Shared Location' ||
        widget.initialPlaceName == 'Unknown Place') {
      _fetchAddress();
    }
  }

  Future<void> _fetchAddress() async {
    try {
      final placemarks = await placemarkFromCoordinates(
        widget.position.latitude,
        widget.position.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        setState(() {
          // Full breakdown to match the client's requested reference format
          // (street, area, city, district, state, PIN) — country
          // deliberately excluded, same reasoning as _formatAddress above:
          // this app is India-only, so it adds nothing. This is a SEPARATE
          // address-resolution path from _formatAddress (this one only
          // activates when the backend's own place name comes back
          // "Unknown"/"Unknown Location"/"Shared Location" and falls back
          // to resolving the coordinates client-side via the geocoding
          // package's structured Placemark fields) — it was previously
          // only building street/subLocality/locality, silently dropping
          // district/state/PIN whenever this fallback fired.
          _resolvedAddress = [
            place.street,
            place.subLocality,
            place.locality,
            place.subAdministrativeArea, // district
            place.administrativeArea, // state
            place.postalCode, // PIN code
          ].where((e) => e != null && e.isNotEmpty).join(', ');

          if (_resolvedAddress!.isEmpty) {
            _resolvedAddress = place.name ?? widget.initialPlaceName;
          }
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _resolvedAddress ?? widget.initialPlaceName;
    // childName now renders separately, on the same row as the
    // refresh/notification/share icons (see _buildLocationCardOnly) — this
    // widget only owns the "is at <place>" line underneath it.
    return Text(
      'is at $displayText',
      style: GoogleFonts.poppins(
        // Was 24 — the full street/area/city/district/state/PIN address now
        // shown here (see _fetchAddress above) runs much longer than the
        // short place names this size was originally tuned for; 14 keeps a
        // multi-line full address readable without dominating the card.
        fontSize: 14.0.sp,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF0C1D37),
        height: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Trip Status Card
// ─────────────────────────────────────────────────────────────────────────────

class _LiveTripCard extends StatelessWidget {
  final ActiveTrip? activeTrip;
  // True when the device isn't currently reachable/live (see
  // _HomePageState._isDeviceOffline) — the trip itself may still be
  // "ongoing" server-side, but a green "LIVE" badge next to it would
  // contradict an OFFLINE badge shown elsewhere on the same screen.
  final bool isDeviceOffline;

  const _LiveTripCard({this.activeTrip, this.isDeviceOffline = false});

  static IconData _activityIcon(String? activity) {
    switch (activity?.toLowerCase()) {
      case 'walking':
      case 'walk':
        return Icons.directions_walk;
      case 'cycling':
      case 'bike':
        return Icons.pedal_bike;
      case 'running':
      case 'run':
        return Icons.directions_run;
      case 'stationary':
      case 'still':
        return Icons.location_on;
      case 'vehicle':
      case 'driving':
      default:
        return Icons.directions_car;
    }
  }

  static String _activityLabel(String? activity) {
    switch (activity?.toLowerCase()) {
      case 'walking':
      case 'walk':
        return 'Walking';
      case 'cycling':
      case 'bike':
        return 'Cycling';
      case 'running':
      case 'run':
        return 'Running';
      case 'stationary':
      case 'still':
        return 'Stationary';
      case 'vehicle':
      case 'driving':
      default:
        return 'Vehicle';
    }
  }

  static String _formatDistance(double meters) {
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '< 1 min';
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours} hr ${mins} min';
    }
    return '${mins} min';
  }

  static String _startedAgoLabel(DateTime? startedAt) {
    if (startedAt == null) return '';
    final diff = DateTime.now().toUtc().difference(startedAt.toUtc());
    final mins = diff.inMinutes;
    if (mins < 1) return 'Started just now';
    if (mins < 60) return 'Started $mins min ago';
    return 'Started ${diff.inHours} hr ago';
  }

  @override
  Widget build(BuildContext context) {
    final bool show = activeTrip != null && activeTrip!.isActive;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: show
          ? _buildCard(context, activeTrip!, isDeviceOffline)
          : const SizedBox.shrink(key: ValueKey('live_trip_hidden')),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ActiveTrip trip,
    bool isDeviceOffline,
  ) {
    final icon = _activityIcon(trip.activity);
    final label = _activityLabel(trip.activity);
    final distance = _formatDistance(trip.distanceMeters);
    final duration = _formatDuration(trip.durationSeconds);
    final agoLabel = _startedAgoLabel(trip.startedAt);

    return Container(
      key: const ValueKey('live_trip_card'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCFCE7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Left: icon + labels
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Currently Travelling',
                    style: GoogleFonts.poppins(
                      fontSize: 13.0.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0C1D37),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 11.0.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  if (agoLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      agoLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 11.0.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Center: stats
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  distance,
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  duration,
                  style: GoogleFonts.poppins(
                    fontSize: 11.0.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            // Right: LIVE / STALE badge — must never say LIVE while the
            // device itself is reported offline elsewhere on this screen.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDeviceOffline
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isDeviceOffline ? 'STALE' : 'LIVE',
                style: GoogleFonts.poppins(
                  fontSize: 10.0.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
