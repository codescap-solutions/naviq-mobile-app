class ApiEndpoints {
  // Base URL
  static const String baseUrl = 'https://naviq-server.codescap.com/api/v1/';

  // Auth Endpoints
  static const String sendOtp = 'users/request-otp';
  static const String verifyOtp = 'users/verify-otp';
  static const String registerUser = 'users';
  static const String refreshToken = 'auth/refresh-token';
  static const String logout = 'auth/logout';

  //child Endpoints
  static const String childLogin = 'child/login';
  static const String createChild = 'child/create';
  static const String uploadAvatar = 'child/upload-avatar';
  static const String postDeviceInfo = 'child/device-status';
  static const String postLocation = 'child/location';
  static const String postGeofenceEvent = 'child/geofence-event';
  static const String getChildGeofences = 'child/geofences';
  static const String postActivity = 'child/activity';
  static const String postAppUsage = 'app-usage';
  static const String childAvailableIcons = 'child/available-icons';
  static const String childUploadAppIcons = 'child/upload-icons';
  static const String childContacts = 'child/contacts';
  static const String screenTimeApps = 'screen-time/apps';
  static const String appMappings = 'app-mappings';

  //parent Endpoints
  static const String getHome = 'parent/home';
  static const String parentContacts = 'parent/contacts';
  static String parentContactDetail(String id) => 'parent/contacts/$id';
  static const String getDeviceStatus = 'parent/device-status';
  static const String getScreenTime = 'parent/screentime';
  static const String getTrips = 'parent/trips';
  static const String parentChildren = 'parent/children';
  static const String linkChild = 'parent/link-child';
  static String deleteChild(String childId) => 'parent/children/$childId';
  static String updateChild(String childId) => 'parent/children/$childId';
  static String getTripDetail(String tripId) => 'parent/trip/$tripId';
  static String postTripLocation(String childId) =>
      'trip-tracking/$childId/locations';
  static String getTrackingSnapshot(String childId) =>
      'parent/child/$childId/tracking/snapshot';
  static const String refreshChild = 'parent/refresh-child';
  static const String guardians = 'parent/guardians';
  static String guardianDetail(String id) => 'parent/guardians/$id';
  static String guardianAvatar(String id) => 'parent/guardians/$id/avatar';
  static String postTripEnd(String childId) =>
      'trip-tracking/$childId/end';
  static const String getAppUsage = 'app-usage';
  static const String getAppUsageSummary = 'app-usage/summary';

  // App Lock Endpoints
  static const String parentLockedApps = 'parent/locked-apps';
  static const String childLockedApps = 'child/locked-apps';
  static const String lockApps = 'lock-apps';
  static const String unlockApps = 'unlock-apps';

  // Daily App Time Limit + Ask-for-More-Time Endpoints
  static const String appTimeLimits = 'app-time-limits';
  static const String timeExtensionRequests = 'time-extension-requests';
  static String resolveTimeExtensionRequest(String id) =>
      'time-extension-requests/$id/resolve';

  // Child-Requests-Logout Endpoints
  static const String logoutRequests = 'logout-requests';
  static String resolveLogoutRequest(String id) =>
      'logout-requests/$id/resolve';

  // FCM Token endpoints
  static const String parentFcmToken = 'fcm-token/parent';
  static const String childFcmToken = 'fcm-token/child';

  // SOS endpoint
  static const String childSOS = 'child/sos';

  // Places & Geofence (Unified) Endpoints
  static const String places = 'places';
  static String placeDetail(String id) => 'places/$id';
  static String assignChildToPlace(String id) => 'places/$id/assign-child';
  static String unassignChildFromPlace(String id) =>
      'places/$id/unassign-child';
  static String assignAllChildrenToPlace(String id) =>
      'places/$id/assign-all-children';
  static String togglePlaceNotification(String id) =>
      'places/$id/toggle-notification';
  // Settings endpoints
  static const String updateChildSettings = 'parent/child-settings';
  static const String webFilter = 'parent/web-filter';
  static const String restrictDeletion = 'parent/restrict-deletion';
  static const String notificationPreferences = 'notification-preferences';

  // Chat Endpoints
  static const String chat = 'chat';
  static String chatMessages(String chatId) => 'chat/$chatId/messages';
  static String markChatRead(String chatId) => 'chat/$chatId/read';

  // Location Sharing Endpoints
  static const String requestLocation = 'location/request';
  static String respondToLocationRequest(String id) => 'location/request/$id/respond';
  static String revokeLocationShare(String id) => 'location/share/$id/revoke';
  static const String activeOutgoingShares = 'location/shares/active';

  // Subscription Endpoints
  static const String getSubscriptionPlans = 'subscriptions/plans';
}
