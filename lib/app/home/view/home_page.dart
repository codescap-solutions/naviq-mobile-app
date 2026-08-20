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
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';

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
  final GlobalKey<_HomeMapBackgroundState> _mapBackgroundKey = GlobalKey();
  double _mapHeightFraction = 0.80; // 92% initial height (Expanded)
  // ─────────────────────────────────────────────────────────────────────────

  StreamSubscription? _notificationSubscription;
  StreamSubscription? _foregroundSubscription;
  Map<String, dynamic>? _activeSharedChildData;
  bool _viewingSharedChild = false;
  bool _isLocationShareSheetOpen = false;
  bool _isTimeExtensionSheetOpen = false;
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
    double targetFraction = _mapHeightFraction;

    if (_mapHeightFraction == 0.92) {
      // Collapse threshold
      if (offset > 60) {
        targetFraction = 0.60;
      }
    } else if (_mapHeightFraction == 0.60) {
      // Collapse or Expand thresholds
      if (offset > 240) {
        targetFraction = 0.35;
      } else if (offset < 40) {
        targetFraction = 0.92;
      }
    } else if (_mapHeightFraction == 0.35) {
      // Expand threshold
      if (offset < 160) {
        targetFraction = 0.60;
      }
    }

    if (targetFraction != _mapHeightFraction) {
      setState(() {
        _mapHeightFraction = targetFraction;
      });
    }
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
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
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
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      keyboardType: TextInputType.text,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
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
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
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
                        style: GoogleFonts.manrope(
                          fontSize: 18,
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
                      style: GoogleFonts.manrope(
                        fontSize: 14,
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
                            style: GoogleFonts.manrope(
                              fontSize: 18,
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
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0C1D37),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Sent just now',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
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
                                        style: GoogleFonts.manrope(
                                          fontSize: 12,
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
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0C1D37),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: ['15 min', '30 min', '1 hour', '2 hours'].map(
                          (duration) {
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
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF0C1D37),
                                  ),
                                ),
                              ),
                            );
                          },
                        ).toList(),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select kids to share location',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
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
                                                style: GoogleFonts.manrope(
                                                  fontSize: 16,
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
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF0C1D37),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    displayAge,
                                    style: GoogleFonts.manrope(
                                      fontSize: 10,
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
                                  style: GoogleFonts.manrope(
                                    fontSize: 16,
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
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Location will only be shared for the selected duration. You can revoke access anytime.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
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
                style: GoogleFonts.manrope(
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
                    style: GoogleFonts.manrope(
                      fontSize: 13,
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
                    style: GoogleFonts.manrope(
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
                          style: GoogleFonts.manrope(
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
    String? avatar,
  ) async {
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

  // Sourced from trackingSnapshot.latestLocation.deviceTimestamp specifically
  // — the same authoritative timestamp uiDirective.displayState itself was
  // computed from server-side — rather than state.currentLocation.since
  // (driven by the separate REST/socket location stream, see
  // HomepageBloc._isNewerLocationUpdate). Keeping the visible "last updated"
  // time tied to the same source the status badge is computed from avoids
  // the two ever telling a parent a contradictory story. Shown regardless of
  // whether location is off, so a parent isn't left with zero freshness
  // information when the badge alone can't fully explain what's going on.
  String? _formatLastUpdated(DateTime? deviceTimestamp) {
    if (deviceTimestamp == null) return null;
    final diff = DateTime.now().toUtc().difference(deviceTimestamp.toUtc());
    if (diff.isNegative) return 'Last updated just now';
    if (diff.inSeconds < 90) return 'Last updated just now';
    if (diff.inMinutes < 60) return 'Last updated ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Last updated ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Last updated yesterday';
    if (diff.inDays < 7) return 'Last updated ${diff.inDays}d ago';
    return 'Last updated ${deviceTimestamp.toLocal().toString().split('.').first}';
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
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
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
              color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
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
            style: GoogleFonts.manrope(
              fontSize: 11,
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

        final childName =
            _sharedPrefsService.getString('child_name') ?? 'Ananya';
        final matchingPlace = _findMatchingPlace(
          state.currentLocation?.lat,
          state.currentLocation?.lng,
        );
        final placeName = matchingPlace != null
            ? matchingPlace.name
            : (state.currentLocation?.address != null
                  ? _formatAddress(state.currentLocation?.address)
                  : 'Unknown Place');

        final double screenHeight = MediaQuery.of(context).size.height;

        return CustomScrollView(
          controller: _homeScrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // Sliver 1: Map section — height driven by scroll position
            SliverToBoxAdapter(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: screenHeight * _mapHeightFraction,
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
                            loadCustomMarker: _loadCustomMarker,
                            activeSharedChildData: _activeSharedChildData,
                            viewingSharedChild: _viewingSharedChild,
                            ownChildLocation: state.currentLocation != null
                                ? LatLng(
                                    state.currentLocation!.lat,
                                    state.currentLocation!.lng,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),

                    // Layer 1.5: Floating Overlay Avatar for Shared Kid
                    () {
                      final floatingChildren = state.sharedChildren.isNotEmpty
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
                                      latitude: _activeSharedChildData!['lat'],
                                      longitude: _activeSharedChildData!['lng'],
                                      batteryPercentage:
                                          _activeSharedChildData!['battery_percentage'] ??
                                          50,
                                      avatar: _activeSharedChildData!['avatar'],
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
                                .substring(0, min(2, child.childName.length))
                                .toUpperCase();

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _activeSharedChildData = {
                                          'child_id': child.childId,
                                          'child_name': child.childName,
                                          'avatar':
                                              child.avatar ?? 'Boy 03.png',
                                          'lat': child.latitude,
                                          'lng': child.longitude,
                                          'expires_at': child.expiresAt,
                                          'battery_percentage':
                                              child.batteryPercentage,
                                          'last_sync_at': child.lastSyncAt,
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
                                            color: Colors.black.withOpacity(
                                              0.15,
                                            ),
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
                                                    (child.avatar!.startsWith(
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
                                                                ? child.avatar!
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
                                                        style:
                                                            GoogleFonts.manrope(
                                                              fontSize: 14,
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
                                              style: GoogleFonts.manrope(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF0066FF),
                                              ),
                                            ),
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981),
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
                                      borderRadius: BorderRadius.circular(8),
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
                                      style: GoogleFonts.manrope(
                                        fontSize: 10,
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
                    if (_viewingSharedChild && _activeSharedChildData != null)
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
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                        style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF0C1D37),
                                        ),
                                      ),
                                      Text(
                                        _getRemainingTimeText(
                                          _activeSharedChildData!['expires_at'],
                                        ),
                                        style: GoogleFonts.manrope(
                                          fontSize: 11,
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
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _viewingSharedChild = false;
                                  });
                                },
                                child: Text(
                                  'Switch to Home',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Layer FAB: floating "Map" FAB visible only when collapsed (35% height)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      bottom: (_mapHeightFraction == 0.35) ? 96 : -60,
                      right: 16,
                      child: AnimatedOpacity(
                        opacity: (_mapHeightFraction == 0.35) ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _mapHeightFraction = 0.92;
                            });
                            if (_homeScrollController.hasClients) {
                              _homeScrollController.animateTo(
                                0,
                                duration: const Duration(milliseconds: 300),
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
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
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
                      bottom: 36,
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

                    // Layer 2: Overlay Location Card at the bottom of the map
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: (_mapHeightFraction == 0.35)
                          ? 90
                          : 20, // Responsive to prevent overlap
                      child: _buildLocationCardOnly(
                        context,
                        _viewingSharedChild && _activeSharedChildData != null
                            ? _activeSharedChildData!['child_name']
                            : childName,
                        _viewingSharedChild && _activeSharedChildData != null
                            ? 'Shared Location'
                            : placeName,
                        state,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Sliver 2: Scrollable content cards below the map
            if (!_viewingSharedChild)
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Live Trip Status Card — shown only when actively travelling
                    _LiveTripCard(
                      activeTrip: state.activeTrip,
                      isDeviceOffline: _isDeviceOffline(state),
                    ),

                    // 2. Scroll & Geo Guard Feature Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildFeatureCard(
                            title: 'Scroll',
                            subtitle: 'Social Media & Apps',
                            statusText:
                                state.features?.scrollStatusText ??
                                '0 Apps Locked',
                            icon: Icons.smartphone_rounded,
                            cardBg: const Color(0xFFEFF6FF),
                            borderCol: const Color(0xFFDBEAFE),
                            iconCol: const Color(0xFF3B82F6),
                            statusBg: const Color(0xFFDBEAFE),
                            statusTextCol: const Color(0xFF1D4ED8),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SocialAppsView(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFeatureCard(
                            title: 'Geo Guard',
                            subtitle: 'Places & Geofencing',
                            statusText:
                                state.features?.geoGuardStatusText ??
                                '0 Fencing',
                            icon: Icons.location_on_outlined,
                            cardBg: const Color(0xFFFFF7ED),
                            borderCol: const Color(0xFFFFEDD5),
                            iconCol: const Color(0xFFF97316),
                            statusBg: const Color(0xFFFFEDD5),
                            statusTextCol: const Color(0xFFC2410C),
                            onTap: () {
                              final childId = _sharedPrefsService.getString(
                                'child_id',
                              );
                              final parentId = _sharedPrefsService.getString(
                                'parent_id',
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GeoFencingView(
                                    childId: childId,
                                    parentId: parentId,
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
                    const SizedBox(height: 16),

                    // 3. Today's Route Map Card
                    _buildRouteMapCard(context),
                    const SizedBox(height: 16),

                    // 4. Upgrade to Pro Banner
                    _buildUpgradeProBanner(),
                    const SizedBox(height: 24),

                    // 5. Screentime Today Section
                    _buildScreentimeSection(context),
                    const SizedBox(height: 24),

                    // 6. Shortcuts Section
                    _buildShortcutsSection(context),
                    const SizedBox(height: 24),

                    // 7. Help Centre Section
                    _buildHelpCentreSection(context),
                  ]),
                ),
              ),
          ],
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
    // Distinct from isLocationOff: the device/GPS toggle is fine, but the
    // backend itself says this isn't live data right now (OFFLINE,
    // UNREACHABLE, STALE, ...). Reusing showLiveMarker rather than listing
    // displayState strings here means this inherits the backend's own
    // freshness judgement call (e.g. BACKGROUND_RESTRICTED only counts as
    // non-live once it's actually stale) instead of a second, possibly
    // out-of-sync copy of that logic living here too.
    final isDeviceOffline = _isDeviceOffline(state);
    // isDeviceOffline above only means "not live right now" (server
    // show_live_marker: false) — true for both a genuinely unreachable
    // device AND a device that's ONLINE but whose last location fix went
    // stale. Both cases share the same amber pill/color, but the *word*
    // shown must not say "OFFLINE" for the latter — that contradicts the
    // server's own device_status: ONLINE (and the sibling live-trip badge,
    // which already says "STALE" for the identical condition).
    // Compare against displayState, not the raw device_status field — the
    // server sends device_status as ONLINE/OFFLINE/UNREACHABLE/... (multiple
    // distinct strings for "not actually connected"), so matching only the
    // literal 'OFFLINE' string missed UNREACHABLE and any other future
    // variant, silently falling through to "Stale" for a genuinely offline
    // device. displayState is already the single curated field this screen
    // treats as authoritative elsewhere (isLocationOff above) — within the
    // non-live bucket, STALE is the only "still probably fine" reason;
    // everything else (OFFLINE, UNREACHABLE, BACKGROUND_RESTRICTED, ...)
    // means the device really isn't reporting.
    final isReallyOffline = displayState != 'STALE';
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
    final showAsOffline = isDeviceOffline;

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
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isLocationOff
                      ? const Color(0xFFEF4444)
                      : (showAsOffline
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF10B981)),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isLocationOff
                    ? 'LOCATION OFF'
                    : (showAsOffline
                          ? (isReallyOffline
                                ? 'OFFLINE'
                                : _staleBadgeWord(
                                    trackingSnapshot?.latestLocation,
                                  ))
                          : 'ACTIVE NOW'),
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isLocationOff
                      ? const Color(0xFFEF4444)
                      : (showAsOffline
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF94A3B8)),
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
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
                            style: GoogleFonts.manrope(
                              fontSize: 10,
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
                    Icons.share_outlined,
                    size: 16,
                    color: Color(0xFF0C1D37),
                  ),
                  onPressed: () {
                    Share.share('$childName is at $placeName');
                  },
                ),
              ),
            ],
          ),
          if (!_viewingSharedChild &&
              _formatLastUpdated(
                    trackingSnapshot?.latestLocation?.deviceTimestamp,
                  ) !=
                  null) ...[
            const SizedBox(height: 4),
            Text(
              _formatLastUpdated(
                trackingSnapshot?.latestLocation?.deviceTimestamp,
              )!,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
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
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLocationStatusPill(
                isLocationOff
                    ? Icons.location_off_rounded
                    : (showAsOffline
                          ? Icons.cloud_off_rounded
                          : Icons.access_time_rounded),
                isLocationOff
                    ? 'Location off'
                    : (showAsOffline
                          ? (isReallyOffline
                                ? 'Offline'
                                : _staleDurationPill(
                                    trackingSnapshot?.latestLocation,
                                  ))
                          : (_viewingSharedChild &&
                                    _activeSharedChildData != null
                                ? _formatSinceTime(
                                    _activeSharedChildData!['last_sync_at']
                                        ?.toString(),
                                  )
                                : _formatSinceTime(
                                    state.currentLocation?.since,
                                  ))),
                backgroundColor: isLocationOff
                    ? const Color(0xFFFEE2E2)
                    : (showAsOffline ? const Color(0xFFFEF3C7) : null),
                contentColor: isLocationOff
                    ? const Color(0xFFDC2626)
                    : (showAsOffline ? const Color(0xFFB45309) : null),
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
            ],
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
            style: GoogleFonts.manrope(
              fontSize: 12,
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
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
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
                        style: GoogleFonts.manrope(
                          fontSize: 11,
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
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.alt_route_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Route Map",
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C1D37),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              distance,
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              newLoc,
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
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
            style: GoogleFonts.manrope(
              fontSize: 12.5,
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
    final bool firstActive = listNodes.isNotEmpty && listNodes[0].isActive;
    children.add(
      Padding(
        padding: const EdgeInsets.only(
          top: 9.5,
        ), // (22 circle height / 2) - (3 line height / 2) = 11 - 1.5 = 9.5
        child: Container(
          width: 12,
          height: 3,
          color: firstActive
              ? const Color(0xFF0066FF)
              : const Color(0xFFE2E8F0),
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

    // Right Tail (matches color of last node)
    final bool lastActive = listNodes.isNotEmpty && listNodes.last.isActive;
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 9.5),
        child: Container(
          width: 12,
          height: 3,
          color: lastActive ? const Color(0xFF0066FF) : const Color(0xFFE2E8F0),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTimelineNode({
    required String label,
    required String time,
    required bool isActive,
    required bool isHighlighted,
  }) {
    return Column(
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
          style: GoogleFonts.manrope(
            fontSize: 12,
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
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
            color: isHighlighted
                ? const Color(0xFF94A3B8)
                : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineConnector(bool isActive) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(top: 9.5),
        child: Container(
          height: 3,
          color: isActive ? const Color(0xFF0066FF) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _buildUpgradeProBanner() {
    return Container(
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
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                "Unlock all premium features",
                style: GoogleFonts.manrope(
                  fontSize: 11.5,
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
              style: GoogleFonts.manrope(
                fontSize: 20,
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
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E40AF),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              limitText,
                              style: GoogleFonts.manrope(
                                fontSize: 10.5,
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
              style: GoogleFonts.manrope(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Screen time usage will be displayed here.",
              style: GoogleFonts.manrope(
                fontSize: 11.5,
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
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0C1D37),
                ),
              ),
              Text(
                item.usageDuration,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 10.5,
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
          style: GoogleFonts.manrope(
            fontSize: 20,
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
              style: GoogleFonts.manrope(
                fontSize: 10,
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
          style: GoogleFonts.manrope(
            fontSize: 20,
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
        style: GoogleFonts.manrope(
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0C1D37),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.manrope(
          fontSize: 11,
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
  final Future<BitmapDescriptor?> Function(int, String?) loadCustomMarker;
  final Map<String, dynamic>? activeSharedChildData;
  final bool viewingSharedChild;
  final LatLng? ownChildLocation;

  const _HomeMapBackground({
    super.key,
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

  Future<void> _loadMarkerIcon(int batteryPercentage, String? avatar) async {
    if (_cachedMarkerIcon != null &&
        _cachedBatteryPercentage == batteryPercentage &&
        _cachedAvatar == avatar) {
      return;
    }
    final icon = await widget.loadCustomMarker(batteryPercentage, avatar);
    if (!mounted) return;
    setState(() {
      _cachedMarkerIcon = icon;
      _cachedBatteryPercentage = batteryPercentage;
      _cachedAvatar = avatar;
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
          return locChanged || batteryChanged;
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
          _loadMarkerIcon(battery, avatar);

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
            return locChanged || batteryChanged;
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
          _loadMarkerIcon(battery, avatar);

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
                myLocationEnabled: true,
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
              if (!widget.viewingSharedChild &&
                  state is HomepageSuccess &&
                  state.trackingSnapshot != null &&
                  // Only show the banner when the device is genuinely not live
                  // (showLiveMarker drives the OFFLINE/STALE state everywhere else
                  // on this screen — tying the banner to the same signal prevents
                  // a stale/cached banner_message from appearing while the backend
                  // simultaneously reports display_state: LIVE / show_live_marker: true).
                  !state.trackingSnapshot!.uiDirective.showLiveMarker &&
                  state.trackingSnapshot!.uiDirective.bannerMessage.isNotEmpty &&
                  // ...but not when the last known fix sits at a known place
                  // (Home/School/...), regardless of whether the reason is
                  // STALE or the device having gone fully OFFLINE/UNREACHABLE
                  // since. Matched against FindMyKids' own behavior for the
                  // identical case (device offline a full day, parked at a
                  // saved place): it shows a calm "At home • 1 day" label,
                  // no alarm banner — a device that's silent while sitting
                  // exactly where it was last confirmed isn't read as
                  // urgent by a parent either way, so training them to
                  // dismiss the same black banner for it just teaches them
                  // to ignore it when it matters. Location-service problems
                  // (PERMISSION_DENIED, GPS_DISABLED) are a different kind
                  // of signal — those need the child to act, not just "wait
                  // it out" — so they keep the banner regardless of place.
                  !((state.trackingSnapshot!.uiDirective.displayState !=
                              'PERMISSION_DENIED' &&
                          state.trackingSnapshot!.uiDirective.displayState !=
                              'GPS_DISABLED') &&
                      (state.currentLocation?.placeName ?? '').isNotEmpty &&
                      (state.currentLocation?.placeName ?? '').toLowerCase() !=
                          'unknown'))
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    color: Colors.black.withOpacity(0.9),
                    child: Text(
                      state.trackingSnapshot!.uiDirective.bannerMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
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
    if (widget.initialPlaceName == 'Unknown Location' ||
        widget.initialPlaceName == 'Unknown' ||
        widget.initialPlaceName == 'Shared Location') {
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
    return Text(
      '${widget.childName} is  \n$displayText',
      style: GoogleFonts.manrope(
        // Was 24 — the full street/area/city/district/state/PIN address now
        // shown here (see _fetchAddress above) runs much longer than the
        // short place names this size was originally tuned for; 14 keeps a
        // multi-line full address readable without dominating the card.
        fontSize: 14,
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
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0C1D37),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  if (agoLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      agoLabel,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
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
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  duration,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
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
                style: GoogleFonts.manrope(
                  fontSize: 10,
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
