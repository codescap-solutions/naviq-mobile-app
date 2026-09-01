import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/child_profile.dart';
import '../utils/app_logger.dart';

class SharedPrefsService {
  static SharedPreferences? _prefs;

  // Initialize SharedPreferences
  static final _secureStorage = FlutterSecureStorage();
  static String? _cachedAuthToken;
  static String? _cachedRefreshToken;

  // Initialize SharedPreferences and load secure token
  // Initialize SharedPreferences and load secure token
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Migration: Check for legacy token in SharedPreferences
    // We only migrate IF SecureStorage works. If it fails, we stick to Prefs.
    String? secureToken;
    bool secureStorageWorking = true;

    try {
      secureToken = await _secureStorage.read(key: 'auth_token');
    } catch (e) {
      secureStorageWorking = false;
      AppLogger.error('SecureStorage not available: $e');
    }

    final legacyToken = _prefs?.getString('auth_token');

    // Diagnostic: secure storage can fail "silently" too — no exception,
    // just an empty read — which looks identical to "no token was ever
    // saved" from the outside. Logging these three inputs separately
    // (instead of only the final loaded/not-loaded outcome) is what's
    // needed to tell apart "this device/isolate genuinely has no token"
    // from "secure storage is unreadable from this execution context" the
    // next time a background-isolate persistent-401 report comes in —
    // this init() runs both in the main app and inside the background
    // location service's own isolate (background_location_service.dart),
    // and only the latter has been seen hitting this.
    AppLogger.info(
      'Token load inputs: secureStorageWorking=$secureStorageWorking, '
      'secureToken=${secureToken != null ? "present" : "null"}, '
      'legacyToken=${legacyToken != null ? "present" : "null"}',
    );

    if (secureStorageWorking &&
        legacyToken != null &&
        legacyToken.isNotEmpty &&
        secureToken == null) {
      // Migrate
      AppLogger.info('Migrating legacy auth token to SecureStorage');
      try {
        await _secureStorage.write(key: 'auth_token', value: legacyToken);
        _cachedAuthToken = legacyToken;
        await _prefs?.remove('auth_token');
      } catch (e) {
        // If write fails, keep legacy
        _cachedAuthToken = legacyToken;
      }
    } else {
      // Load from whichever source is available
      _cachedAuthToken = secureToken ?? legacyToken;
    }

    // Load refresh token if secure storage is working
    if (secureStorageWorking) {
      try {
        _cachedRefreshToken = await _secureStorage.read(key: 'refresh_token');
      } catch (e) {
        AppLogger.error('Error reading refresh token from secure storage: $e');
      }
    }

    AppLogger.info(
      'SharedPreferences and SecureStorage initialized. Token loaded: ${_cachedAuthToken != null}',
    );
  }

  // Get SharedPreferences instance
  static SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('SharedPreferences not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // Auth Token (Secure)
  // Auth Token (Secure with Fallback)
  Future<bool> setAuthToken(String token) async {
    // Always keep a plain-SharedPreferences copy alongside secure storage,
    // not only as an exception-triggered fallback. reloadAuthToken()/init()
    // can only recover from a copy that was actually written somewhere — if
    // the secure-storage WRITE succeeds right now but its READ later fails
    // from some other execution context (e.g. the background-location
    // service's own isolate, possibly in a killed-app state — the class of
    // incident this whole chain of fixes is for), a fallback that was never
    // written is useless. Best-effort: never blocks on or fails the overall
    // call, this is a safety net, not the primary store.
    try {
      await prefs.setString('auth_token', token);
    } catch (e) {
      AppLogger.error('Error saving auth token to shared prefs fallback: $e');
    }

    try {
      await _secureStorage.write(key: 'auth_token', value: token);
      _cachedAuthToken = token;
      return true;
    } catch (e) {
      AppLogger.error('Error saving auth token to secure storage: $e');
      // Secure storage write failed, but the SharedPreferences copy above
      // was still attempted — count it as success if that one landed, since
      // getAuthToken()/reloadAuthToken() already know to fall back to it.
      _cachedAuthToken = token;
      try {
        return prefs.getString('auth_token') == token;
      } catch (_) {
        return false;
      }
    }
  }

  // Force reload of token from storage (useful after migration/re-install)
  Future<void> reloadAuthToken() async {
    try {
      _cachedAuthToken = await _secureStorage.read(key: 'auth_token');
    } catch (e) {
      AppLogger.error('Error reloading secure token: $e');
      _cachedAuthToken = null;
    }

    // Secure storage can return null WITHOUT throwing — e.g. the original
    // setAuthToken() write fell back to plain SharedPreferences (the secure
    // write itself failed on that device) and nothing was ever migrated
    // into secure storage. init() already accounts for that via its
    // migration check on first load; this mirrors it here so a mid-session
    // reload (the 401-retry path, or the request interceptor's "emergency
    // reload if token is missing") doesn't treat "secure storage
    // successfully returned nothing" the same as "there is genuinely no
    // token anywhere" and give up on an otherwise-valid session.
    if (_cachedAuthToken == null || _cachedAuthToken!.isEmpty) {
      try {
        final legacyToken = prefs.getString('auth_token');
        if (legacyToken != null && legacyToken.isNotEmpty) {
          _cachedAuthToken = legacyToken;
        }
      } catch (e2) {
        AppLogger.error('Error reloading shared prefs token: $e2');
      }
    }

    AppLogger.info('Auth token reloaded: ${_cachedAuthToken != null}');
  }

  String? getAuthToken() {
    return _cachedAuthToken;
  }

  Future<bool> removeAuthToken() async {
    // setAuthToken() now always writes a SharedPreferences fallback copy
    // alongside secure storage — that copy must always be cleared here too,
    // or a stale token could survive logout and get picked back up by
    // reloadAuthToken()'s fallback later.
    _cachedAuthToken = null;
    var success = true;

    try {
      await _secureStorage.delete(key: 'auth_token');
    } catch (e) {
      AppLogger.error('Error removing auth token from secure storage: $e');
      success = false;
    }

    try {
      await prefs.remove('auth_token');
    } catch (e) {
      AppLogger.error('Error removing auth token from shared prefs: $e');
      success = false;
    }

    return success;
  }

  // Refresh Token
  Future<bool> setRefreshToken(String token) async {
    try {
      await _secureStorage.write(key: 'refresh_token', value: token);
      _cachedRefreshToken = token;
      return true;
    } catch (e) {
      AppLogger.error('Error saving refresh token: $e');
      return false;
    }
  }

  Future<void> reloadRefreshToken() async {
    try {
      _cachedRefreshToken = await _secureStorage.read(key: 'refresh_token');
    } catch (e) {
      AppLogger.error('Error reloading refresh token: $e');
    }
  }

  String? getRefreshToken() {
    return _cachedRefreshToken;
  }

  Future<bool> removeRefreshToken() async {
    try {
      await _secureStorage.delete(key: 'refresh_token');
      _cachedRefreshToken = null;
      return true;
    } catch (e) {
      AppLogger.error('Error removing refresh token: $e');
      return false;
    }
  }

  // User ID
  Future<bool> setUserId(String userId) async {
    try {
      return await prefs.setString('user_id', userId);
    } catch (e) {
      AppLogger.error('Error saving user ID: $e');
      return false;
    }
  }

  String? getUserId() {
    try {
      return prefs.getString('user_id');
    } catch (e) {
      AppLogger.error('Error getting user ID: $e');
      return null;
    }
  }

  Future<bool> removeUserId() async {
    try {
      return await prefs.remove('user_id');
    } catch (e) {
      AppLogger.error('Error removing user ID: $e');
      return false;
    }
  }

  // User Phone Number
  Future<bool> setUserPhone(String phone) async {
    try {
      return await prefs.setString('user_phone', phone);
    } catch (e) {
      AppLogger.error('Error saving user phone: $e');
      return false;
    }
  }

  String? getUserPhone() {
    try {
      return prefs.getString('user_phone');
    } catch (e) {
      AppLogger.error('Error getting user phone: $e');
      return null;
    }
  }

  Future<bool> removeUserPhone() async {
    try {
      return await prefs.remove('user_phone');
    } catch (e) {
      AppLogger.error('Error removing user phone: $e');
      return false;
    }
  }

  // App Settings
  Future<bool> setBool(String key, bool value) async {
    try {
      return await prefs.setBool(key, value);
    } catch (e) {
      AppLogger.error('Error saving bool $key: $e');
      return false;
    }
  }

  bool getBool(String key, {bool defaultValue = false}) {
    try {
      return prefs.getBool(key) ?? defaultValue;
    } catch (e) {
      AppLogger.error('Error getting bool $key: $e');
      return defaultValue;
    }
  }

  Future<bool> setString(String key, String value) async {
    try {
      return await prefs.setString(key, value);
    } catch (e) {
      AppLogger.error('Error saving string $key: $e');
      return false;
    }
  }

  String? getString(String key) {
    try {
      return prefs.getString(key);
    } catch (e) {
      AppLogger.error('Error getting string $key: $e');
      return null;
    }
  }

  Future<bool> setInt(String key, int value) async {
    try {
      return await prefs.setInt(key, value);
    } catch (e) {
      AppLogger.error('Error saving int $key: $e');
      return false;
    }
  }

  int? getInt(String key) {
    try {
      return prefs.getInt(key);
    } catch (e) {
      AppLogger.error('Error getting int $key: $e');
      return null;
    }
  }

  Future<bool> setDouble(String key, double value) async {
    try {
      return await prefs.setDouble(key, value);
    } catch (e) {
      AppLogger.error('Error saving double $key: $e');
      return false;
    }
  }

  double? getDouble(String key) {
    try {
      return prefs.getDouble(key);
    } catch (e) {
      AppLogger.error('Error getting double $key: $e');
      return null;
    }
  }

  // Clear all data
  Future<bool> clearAll() async {
    try {
      return await prefs.clear();
    } catch (e) {
      AppLogger.error('Error clearing all data: $e');
      return false;
    }
  }

  // Check if user is logged in
  bool isLoggedIn() {
    final token = getAuthToken();
    final userId = getUserId();
    return token != null &&
        token.isNotEmpty &&
        userId != null &&
        userId.isNotEmpty;
  }

  // Check if logged in user is a Parent
  bool get isParent {
    final parentId = getString('parent_id');
    return parentId != null && parentId.isNotEmpty;
  }

  bool get isPrimaryParent {
    return getBool('is_primary_parent', defaultValue: true);
  }

  // Logout user
  //
  // Used to remove only 6 specific keys (auth/refresh token, user id/phone,
  // child id, parent id). Every other cached key this service writes —
  // parent_name/parent_avatar/parents_contacts, child_name/child_avatar/
  // child_code, stored_children, stored_notifications, block_18plus,
  // isPrimaryParent, and anything a future feature adds — survived a
  // logout untouched. On a shared device (or the same person logging back
  // in as a different role/child), the next session's screens could
  // briefly — or permanently, for anything never re-fetched — show the
  // previous account's cached name, avatar, contacts, or settings toggles
  // before/without a fresh load overwriting them. A full clear() is the
  // only version of this that can't silently miss a key some other screen
  // added later.
  Future<bool> logout() async {
    try {
      await prefs.clear();

      AppLogger.info('User logged out successfully — all local data cleared');
      return true;
    } catch (e) {
      AppLogger.error('Error during logout: $e');
      return false;
    }
  }

  Future<bool> removeChildId() async {
    try {
      return await prefs.remove('child_id');
    } catch (e) {
      AppLogger.error('Error removing child ID: $e');
      return false;
    }
  }

  Future<bool> removeParentId() async {
    try {
      return await prefs.remove('parent_id');
    } catch (e) {
      AppLogger.error('Error removing parent ID: $e');
      return false;
    }
  }

  // Multi-Child Support
  Future<bool> saveChildren(List<ChildProfile> children) async {
    try {
      final String encoded = json.encode(
        children.map((e) => e.toMap()).toList(),
      );
      return await prefs.setString('stored_children', encoded);
    } catch (e) {
      AppLogger.error('Error saving children list: $e');
      return false;
    }
  }

  List<ChildProfile> getChildren() {
    try {
      final String? encoded = prefs.getString('stored_children');
      if (encoded == null) return [];
      final List<dynamic> decoded = json.decode(encoded);
      return decoded.map((e) => ChildProfile.fromMap(e)).toList();
    } catch (e) {
      AppLogger.error('Error getting children list: $e');
      return [];
    }
  }

  Future<bool> addChild(ChildProfile child) async {
    final children = getChildren();
    // Prevent duplicates
    children.removeWhere((element) => element.childId == child.childId);
    children.add(child);
    return await saveChildren(children);
  }

  Future<bool> switchChild(String childId) async {
    final children = getChildren();
    final child = children.firstWhere(
      (element) => element.childId == childId,
      orElse: () => throw Exception('Child not found locally'),
    );

    // Update session data
    await setAuthToken(child.authToken);
    await setString('child_code', child.childCode);
    await setString('child_id', child.childId); // Critical for Home module
    await setUserId(
      child.childId,
    ); // Assuming userId maps to childId in this app context
    await setString('child_name', child.childName);

    // Update last active
    final updatedChildren = children.map((e) {
      if (e.childId == childId) {
        return e.copyWith(lastActiveAt: DateTime.now());
      }
      return e;
    }).toList();
    await saveChildren(updatedChildren);

    return true;
  }

  // Get all notifications
  List<Map<String, dynamic>> getNotifications() {
    try {
      final String? encoded = prefs.getString('stored_notifications');
      if (encoded == null) return [];
      final List<dynamic> decoded = json.decode(encoded);
      return List<Map<String, dynamic>>.from(decoded);
    } catch (e) {
      AppLogger.error('Error getting notifications list: $e');
      return [];
    }
  }

  // Save list of notifications
  Future<bool> saveNotifications(List<Map<String, dynamic>> list) async {
    try {
      final String encoded = json.encode(list);
      return await prefs.setString('stored_notifications', encoded);
    } catch (e) {
      AppLogger.error('Error saving notifications list: $e');
      return false;
    }
  }

  // Add a single notification
  Future<bool> addNotification(Map<String, dynamic> notification) async {
    final list = getNotifications();
    list.insert(0, notification); // Insert at beginning so newest is first
    // Limit to last 100 notifications to prevent storage bloat
    if (list.length > 100) {
      list.removeRange(100, list.length);
    }
    return await saveNotifications(list);
  }

  // Clear notifications
  Future<bool> clearNotifications() async {
    try {
      return await prefs.remove('stored_notifications');
    } catch (e) {
      AppLogger.error('Error clearing notifications: $e');
      return false;
    }
  }

  // Deletion Restriction Settings
  Future<bool> setAllowDelete(bool value) async {
    return await setBool('is_allow_delete', value);
  }

  bool getAllowDelete({bool defaultValue = true}) {
    return getBool('is_allow_delete', defaultValue: defaultValue);
  }
}
