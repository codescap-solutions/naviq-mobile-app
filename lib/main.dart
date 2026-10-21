import 'package:child_track/app/auth/view_model/bloc/auth_bloc.dart';
import 'package:child_track/core/services/connectivity/bloc/connectivity_bloc.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/services/csv_file_logger.dart';
import 'package:child_track/core/services/background_location_service.dart';
import 'package:child_track/core/services/background_task_service.dart';
import 'package:child_track/core/services/lock_sync_service.dart';
import 'package:child_track/core/services/revenue_cat_service.dart';
import 'package:child_track/core/services/subscription_manager.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app/geofencing/view_model/bloc/geofence_bloc.dart';
import 'core/di/injector.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/current_route_tracker.dart';
import 'core/navigation/route_names.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/constants/figma_tokens.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15+ draws a translucent scrim over the 3-button bar; drop it so
  // the white bottom nav flows under the buttons like it does on iOS.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize RevenueCat
  await RevenueCatService.instance.initialize();

  // Initialize SubscriptionManager to start listening for premium status
  await SubscriptionManager.instance.initialize();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize CSV file logger (for foreground logs)
  await CsvFileLogger.instance.init();

  // Initialize dependencies
  await initializeDependencies();

  // Initialize Firebase Notification Service
  await injector<FirebaseNotificationService>().initialize();
  injector<FirebaseNotificationService>().setNavigatorKey(navigatorKey);

  // Initialize LockSyncService for handling app blocking navigation
  injector<LockSyncService>().initialize(navigatorKey);

  // Initialize Background Location Service
  await BackgroundLocationService().initialize();

  // Initialize Background Task Service (WorkManager)
  await BackgroundTaskService.initialize();

  runApp(const ChildTrackApp());
}

class ChildTrackApp extends StatelessWidget {
  const ChildTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ConnectivityBloc>(
          create: (context) => injector<ConnectivityBloc>(),
        ),
        BlocProvider<AuthBloc>(create: (context) => injector<AuthBloc>()),
        BlocProvider<GeofenceBloc>(
          create: (context) => injector<GeofenceBloc>(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [CurrentRouteTracker()],
        title: AppStrings.appTitle,
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        onGenerateRoute: AppRouter.generateRoute,
        builder: (context, widget) {
          return BlocListener<ConnectivityBloc, ConnectivityState>(
            listener: (context, state) {
              if (state is ConnectivityOffline) {
                AppSnackbar.showError(context, AppStrings.networkError);
              }
            },
            child: widget ?? const SizedBox.shrink(),
          );
        },
        home: SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();

    _checkAuthStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    // Add a small delay for splash screen to let the animation finish
    await Future.delayed(const Duration(milliseconds: 2000));

    final childId = injector<SharedPrefsService>().getString('child_id');
    final parentId = injector<SharedPrefsService>().getString('parent_id');
    if (parentId != null && parentId.isNotEmpty) {
      // Re-tag RevenueCat's display name/phone attributes on every cold
      // start for an already-logged-in parent — this is what backfills
      // sessions that authenticated before the tagging was added, since
      // there's no other hook that re-runs for an existing session.
      final sharedPrefs = injector<SharedPrefsService>();
      await RevenueCatService.instance.logIn(
        parentId,
        displayName: sharedPrefs.getString('parent_name'),
        phoneNumber: sharedPrefs.getUserPhone(),
      );
    }
    if (mounted) {
      if (parentId != null && parentId.isNotEmpty) {
        Navigator.pushReplacementNamed(context, RouteNames.home);
      } else if (childId != null && childId.isNotEmpty) {
        Navigator.pushReplacementNamed(context, RouteNames.sos);
      } else {
        Navigator.pushReplacementNamed(context, RouteNames.onBoarding);
      }
      // Flush any appBlocked event that arrived before the navigator was ready.
      // Use a post-frame callback so the replacement route is fully mounted first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        injector<LockSyncService>().navigateIfPending();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            // Figma: 288 x 140 logo with the tagline under it, centred on white.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/splash_logo.png',
                  width: 288,
                  height: 140,
                  fit: BoxFit.contain,
                ),
                // The logo image carries its own bottom margin, so no extra gap.
                // Figma Body Large: Poppins Regular 20 / 28, 0.2 spacing.
                Text(
                  'Accuracy. Safety. Protection',
                  style: FigmaText.bodyLarge.copyWith(color: FigmaColors.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
