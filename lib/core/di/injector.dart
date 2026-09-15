import 'package:child_track/app/childapp/view_model/repository/child_location_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/device_info_service.dart';
import 'package:child_track/core/services/connectivity/bloc/connectivity_bloc.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/services/socket_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dio_client.dart';
import 'package:child_track/core/services/screen_time_sync_service.dart';
import '../services/shared_prefs_service.dart';
import '../services/tracking/tracking_config_service.dart';
import '../../app/auth/view_model/auth_repository.dart';
import '../../app/auth/view_model/bloc/auth_bloc.dart';
import '../../app/home/view_model/bloc/homepage_bloc.dart';
import '../../app/map/view_model/map_bloc.dart';
import '../../app/childapp/view_model/bloc/child_bloc.dart';
import '../../app/addplace/service/saved_places_service.dart';
import '../../app/social_apps/view_model/social_apps_repo.dart';
import '../../app/social_apps/view_model/bloc/social_apps_bloc.dart';
import '../../app/geofencing/view_model/geofence_repository.dart';
import '../../app/geofencing/view_model/bloc/geofence_bloc.dart';
import '../../app/subscription/view_model/subscription_repository.dart';
import 'package:child_track/core/services/lock_sync_service.dart';
import '../../app/social_apps/view_model/app_lock_repository.dart';
import '../../app/social_apps/view_model/bloc/app_lock_bloc.dart';
import '../../app/social_apps/view_model/time_limit_repository.dart';
import '../../app/childapp/view_model/repository/logout_request_repository.dart';
import '../../app/social_apps/view_model/bloc/time_limit_bloc.dart';
import '../services/device_info_service.dart';
import 'package:child_track/core/services/chat_socket_service.dart';
import 'package:child_track/app/chat/view_model/chat_repository.dart';
import 'package:child_track/app/chat/view_model/bloc/chat_bloc.dart';

final GetIt injector = GetIt.instance;

Future<void> initializeDependencies() async {
  // Initialize SharedPreferences
  await SharedPrefsService.init();

  // Register SharedPreferences
  injector.registerSingleton<SharedPreferences>(SharedPrefsService.prefs);

  // Register SharedPrefsService
  injector.registerSingleton<SharedPrefsService>(SharedPrefsService());

  // Register Connectivity (required by ConnectivityBloc)
  injector.registerLazySingleton<Connectivity>(() => Connectivity());

  // Register ConnectivityBloc (required by DioClient)
  injector.registerLazySingleton<ConnectivityBloc>(
    () => ConnectivityBloc(connectivity: injector<Connectivity>()),
  );

  // Register DioClient (requires ConnectivityBloc)
  injector.registerSingleton<DioClient>(
    DioClient(connectivityBloc: injector<ConnectivityBloc>()),
  );

  // Register TrackingConfigService
  injector.registerLazySingleton<TrackingConfigService>(
    () => TrackingConfigService(
      dio: injector<DioClient>(),
      prefs: injector<SharedPrefsService>(),
    ),
  );

  // Register Repositories
  injector.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      dioClient: injector<DioClient>(),
      sharedPrefsService: injector<SharedPrefsService>(),
    ),
  );

  injector.registerLazySingleton<HomeRepository>(
    () => HomeRepository(dioClient: injector<DioClient>()),
  );

  injector.registerLazySingleton<ChildRepo>(
    () => ChildRepo(
      dioClient: injector<DioClient>(),
      sharedPrefsService: injector<SharedPrefsService>(),
    ),
  );
  injector.registerLazySingleton<ChildInfoService>(() => ChildInfoService());

  injector.registerLazySingleton<ChildGoogleMapsRepo>(
    () => ChildGoogleMapsRepo(),
  );

  injector.registerLazySingleton<SavedPlacesService>(
    () => SavedPlacesService(),
  );

  injector.registerLazySingleton<SocketService>(() => SocketService());

  injector.registerLazySingleton<SocialAppsRepository>(
    () => SocialAppsRepository(dioClient: injector<DioClient>()),
  );

  injector.registerLazySingleton<GeofenceRepository>(
    () => GeofenceRepository(
      dioClient: injector<DioClient>(),
      sharedPrefsService: injector<SharedPrefsService>(),
    ),
  );

  injector.registerLazySingleton<SubscriptionRepository>(
    () => SubscriptionRepository(
      dioClient: injector<DioClient>(),
    ),
  );

  // Register blocs
  injector.registerLazySingleton<AuthBloc>(
    () => AuthBloc(
      authRepository: injector<AuthRepository>(),
      sharedPrefsService: injector<SharedPrefsService>(),
    ),
  );
  injector.registerLazySingleton<MapBloc>(() => MapBloc());
  injector.registerLazySingleton<HomepageBloc>(
    () => HomepageBloc(
      homeRepository: injector<HomeRepository>(),
      mapBloc: injector<MapBloc>(),
      sharedPrefsService: injector<SharedPrefsService>(),
      socketService: injector<SocketService>(),
    ),
  );
  injector.registerLazySingleton<ScreenTimeSyncService>(
    () => ScreenTimeSyncService(
      injector<ChildInfoService>(),
      injector<ChildRepo>(),
      injector<SharedPrefsService>(),
      injector<DioClient>(),
    ),
  );

  injector.registerLazySingleton<ChildBloc>(
    () => ChildBloc(
      sharedPrefsService: injector<SharedPrefsService>(),
      deviceInfoService: injector<ChildInfoService>(),
      childRepo: injector<ChildRepo>(),
      childLocationRepo: injector<ChildGoogleMapsRepo>(),
      screenTimeSyncService: injector<ScreenTimeSyncService>(),
    ),
  );

  injector.registerFactory<SocialAppsBloc>(
    () => SocialAppsBloc(
      repository: injector<SocialAppsRepository>(),
      sharedPrefsService: injector<SharedPrefsService>(),
      childInfoService: injector<ChildInfoService>(),
    ),
  );

  injector.registerLazySingleton<GeofenceBloc>(
    () => GeofenceBloc(
      repository: injector<GeofenceRepository>(),
      homeRepository: injector<HomeRepository>(),
    ),
  );

  // Register Firebase Notification Service
  injector.registerLazySingleton<FirebaseNotificationService>(
    () => FirebaseNotificationService(),
  );

  // Register LockSyncService
  injector.registerLazySingleton<LockSyncService>(() => LockSyncService());

  // Register AppLockRepository
  injector.registerLazySingleton<AppLockRepository>(
    () => AppLockRepository(dioClient: injector<DioClient>()),
  );

  // Register AppLockBloc
  injector.registerLazySingleton<AppLockBloc>(
    () => AppLockBloc(
      lockSyncService: injector<LockSyncService>(),
      repository: injector<AppLockRepository>(),
      sharedPrefsService: injector<SharedPrefsService>(),
    ),
  );

  // Register TimeLimitRepository + TimeLimitBloc (daily app time limits +
  // ask-for-more-time flow)
  injector.registerLazySingleton<TimeLimitRepository>(
    () => TimeLimitRepository(dioClient: injector<DioClient>()),
  );
  injector.registerLazySingleton<TimeLimitBloc>(
    () => TimeLimitBloc(
      repository: injector<TimeLimitRepository>(),
      sharedPrefsService: injector<SharedPrefsService>(),
    ),
  );

  // Register LogoutRequestRepository (child-requests-logout flow)
  injector.registerLazySingleton<LogoutRequestRepository>(
    () => LogoutRequestRepository(dioClient: injector<DioClient>()),
  );

  // Register DeviceInfoService
  injector.registerLazySingleton<DeviceInfoService>(() => DeviceInfoService());

  // Register Chat Services
  injector.registerLazySingleton<ChatSocketService>(() => ChatSocketService());
  injector.registerLazySingleton<ChatRepository>(
    () => ChatRepository(dioClient: injector<DioClient>()),
  );
  injector.registerLazySingleton<ChatBloc>(
    () => ChatBloc(
      chatRepository: injector<ChatRepository>(),
      chatSocketService: injector<ChatSocketService>(),
      sharedPrefsService: injector<SharedPrefsService>(),
    ),
  );
}
