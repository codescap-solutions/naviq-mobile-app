import Flutter
import UIKit
import GoogleMaps
import AVFoundation
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import FamilyControls
import ManagedSettings
import DeviceActivity
import SwiftUI
import CoreLocation
import Network
import os.log

// MARK: - AppDelegate
@main
@objc class AppDelegate: FlutterAppDelegate {

    /// Guards against calling startLocationServices() more than once —
    /// applicationDidBecomeActive can fire repeatedly (e.g. after Control
    /// Center dismissal), but the location manager only needs to be armed once.
    private var didStartLocationServices = false

    // MARK: - Properties

    /// Native logger for background diagnostics
    private let log = OSLog(subsystem: "com.truenyx.naviq", category: "BackgroundSync")

    /// Native location manager — caches 5 GPS fields to App Group.
    /// No CLGeocoder: the server derives address from coordinates.
    private let locationManager = CLLocationManager()

    /// Network path monitor — caches connectivity type to App Group.
    private let nwMonitor = NWPathMonitor()
    private let nwQueue   = DispatchQueue(label: "com.truenyx.naviq.nw", qos: .utility)

    /// One-shot pending completion for stale-location refresh
    /// (set by requestFreshLocationWithTimeout, consumed in didUpdateLocations).
    private var pendingFreshLocationCompletion: ((CLLocation?) -> Void)?

    /// Rate limiting for background native syncs from didUpdateLocations
    private var lastBackgroundSyncTime: Date?

    /// Standard URLSession configured for background execution window syncs.
    /// Data tasks with completion handlers are fully supported here.
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 25
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }()

    // MARK: - App Group keys
    private let appGroupID   = "group.com.truenyx.naviq"
    private let kAuthToken   = "com.truenyx.naviq.auth_token"
    private let kApiBaseUrl  = "com.truenyx.naviq.api_base_url"
    private let kChildId     = "com.truenyx.naviq.child_id"
    private let kCachedLat   = "com.truenyx.naviq.cached_lat"
    private let kCachedLng   = "com.truenyx.naviq.cached_lng"
    private let kCachedLocTs = "com.truenyx.naviq.cached_loc_ts"
    private let kCachedAcc   = "com.truenyx.naviq.cached_accuracy"
    private let kCachedSpd   = "com.truenyx.naviq.cached_speed"
    private let kNetworkType = "com.truenyx.naviq.cached_network_type"

    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    // MARK: - application(_:didFinishLaunchingWithOptions:)

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        FirebaseApp.configure()
        GMSServices.provideAPIKey("AIzaSyASaOyJsO7dp01jjv625MI9Tw9HwEeTuQg")
        GeneratedPluginRegistrant.register(with: self)

        // Log launch from remote notification
        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            let dataMap = remoteNotification["data"] as? [String: Any]
            let type = remoteNotification["type"] as? String 
                ?? dataMap?["type"] as? String 
                ?? (remoteNotification["gcm.notification.type"] as? String)
            let action = remoteNotification["action"] as? String 
                ?? dataMap?["action"] as? String
            
            os_log("🚀 App launched from remote notification: type=%{public}@, action=%{public}@", log: log, type: .info, type ?? "nil", action ?? "nil")
            logToExtension("🚀 App launched from remote notification: type=\(type ?? "nil") action=\(action ?? "nil")")
        }

        // Push notification setup
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound],
                completionHandler: { _, _ in }
            )
        } else {
            let settings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }
        application.registerForRemoteNotifications()
        Messaging.messaging().delegate = self

        // App Group sanity check
        if let defaults = sharedDefaults {
            defaults.set(true, forKey: "com.truenyx.naviq.app_group_test")
            let ok = defaults.bool(forKey: "com.truenyx.naviq.app_group_test")
            print("📱 APP GROUP TEST: \(ok ? "SUCCESS ✅" : "FAILED ❌")")
        } else {
            print("📱 APP GROUP TEST: FAILED ❌")
        }

        // Restore Screen Time state
        if #available(iOS 16.0, *) {
            ScreenTimeManager.shared.startMonitoring()
        }

        startNetworkMonitor()

        // startLocationServices() is deliberately NOT called here. It calls
        // CLLocationManager.requestAlwaysAuthorization(), which needs the app
        // to actually be active (foregrounded) to reliably present its system
        // permission alert. It's deferred to applicationDidBecomeActive, by
        // which point the window/rootViewController (auto-created from
        // Main.storyboard) is guaranteed ready.
        IOSNativeGeofenceManager.shared.initialize(locationManager: locationManager)

        // Breadcrumb region exit = "device moved while it may have had no
        // other way to tell us" (see IOSNativeGeofenceManager's breadcrumb
        // docs). Region-monitoring relaunches are driven by iOS's own
        // locationd daemon rather than this process, so this is the one
        // signal observed to still fire after the user force-quits the app —
        // grab/post a fresh fix, then re-arm a new circle at the new
        // position so the next real movement triggers again.
        IOSNativeGeofenceManager.shared.onBreadcrumbCrossed = { [weak self] exitedCenter in
            guard let self = self else { return }
            os_log("🍞 Breadcrumb crossed — running native sync + re-arming", log: self.log, type: .info)
            self.handleNativeDataSync(completionHandler: { [weak self] _ in
                guard let self = self else { return }
                let newCenter = self.locationManager.location?.coordinate ?? exitedCenter
                IOSNativeGeofenceManager.shared.armBreadcrumb(at: newCenter, force: true)
            })
        }

        let controller = window?.rootViewController as! FlutterViewController
        setupChannels(controller: controller)

        // Handle relaunch by iOS location event (e.g. SLC, visits, geofences after swipe-kill)
        if let launchOptions = launchOptions, launchOptions[.location] != nil {
            os_log("📍 App relaunched in background by iOS Location Event after swipe-kill", log: log, type: .info)
            logToExtension("📍 App relaunched by iOS location event")
            handleNativeDataSync(completionHandler: { _ in })
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        if !didStartLocationServices {
            didStartLocationServices = true
            startLocationServices()
        }
    }

    // MARK: - Location Services (Optimization 1, 4, 6)

    func startLocationServices() {
        locationManager.delegate                    = self
        locationManager.desiredAccuracy             = kCLLocationAccuracyBest
        locationManager.distanceFilter              = 10          // metres
        locationManager.activityType                = .otherNavigation  // Opt-6: better bg allocation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        // Deliberately NOT calling requestAlwaysAuthorization() here.
        // applicationDidBecomeActive calls this once on every cold launch —
        // including the very first launch, before the user has even chosen
        // Parent or Child, let alone reached permission_sequence_screen.dart
        // (the child-only onboarding step that's supposed to be the one
        // place this gets asked, only after a child logs in). That made the
        // system location prompt fire immediately at splash for every
        // install, parent devices included — a parent should never be asked
        // for location at all, and a child shouldn't be asked before
        // logging in. Dart's own flow (LocationService
        // .requestAlwaysAllowPermission(), via the geolocator plugin) is
        // what actually drives the authorization prompt at the right
        // moment; authorizationStatus is process-wide, not per
        // CLLocationManager instance, so whatever that flow grants applies
        // here too. The calls below (delegate/config/monitoring) stay —
        // they're inert until authorization exists and pick up
        // automatically once Dart's flow grants it, with no separate
        // native trigger needed.
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        locationManager.startUpdatingLocation()
    }

    // MARK: - Network Monitor (Optimization 5: no synchronize here)

    private func startNetworkMonitor() {
        nwMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let type: String
            if path.usesInterfaceType(.wifi)     { type = "wifi"     }
            else if path.usesInterfaceType(.cellular) { type = "cellular" }
            else if path.status == .satisfied    { type = "cellular" }
            else                                  { type = "none"     }
            // No synchronize() — UserDefaults syncs automatically
            self.sharedDefaults?.set(type, forKey: self.kNetworkType)
        }
        nwMonitor.start(queue: nwQueue)
    }

    // MARK: - Native Remote Notification Handler

    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let dataMap = userInfo["data"] as? [String: Any]
        
        let type = userInfo["type"] as? String
            ?? dataMap?["type"] as? String
            ?? (userInfo["gcm.notification.type"] as? String)
            
        let action = userInfo["action"] as? String
            ?? dataMap?["action"] as? String
            
        let stateString = application.applicationState == .active ? "active" : "background/inactive"
        os_log("📥 iOS Push Received: type=%{public}@, action=%{public}@, appState=%{public}@", log: log, type: .info, type ?? "nil", action ?? "nil", stateString)
        print("AppDelegate: didReceiveRemoteNotification type=\(type ?? "nil") action=\(action ?? "nil")")

        // Backend confirmed payload: type="FORCE_REFRESH_DATA", action="FORCE_REFRESH_DATA"
        // Also supports legacy action="sync_data" and type="SYNC_DATA" for backward compat.
        let isSyncRequest = (
            type == "FORCE_REFRESH_DATA" ||
            type == "SYNC_DATA"          ||
            action == "FORCE_REFRESH_DATA" ||
            action == "sync_data"
        )
        
        logToExtension("📥 Push Rx: type=\(type ?? "nil") action=\(action ?? "nil") isSync=\(isSyncRequest)")
        
        if isSyncRequest {
            print("AppDelegate: 🔄 Native sync triggered")
            
            // If the app is active (foreground), let the Flutter engine's foreground listener handle it
            if application.applicationState == .active {
                os_log("🔄 App is active (foreground), forwarding sync to Flutter engine", log: log, type: .info)
                print("AppDelegate: App is active, forwarding sync request to Flutter engine")
                super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
                return
            }
            
            os_log("🔄 App is backgrounded, executing native background sync", log: log, type: .info)
            logToExtension("🔄 Starting native background sync")
            // Pass push-payload child_id/childId as fallback for first-launch edge case
            let pushChildId = userInfo["child_id"] as? String
                ?? userInfo["childId"] as? String
                ?? dataMap?["child_id"] as? String
                ?? dataMap?["childId"] as? String
                
            handleNativeDataSync(pushPayloadChildId: pushChildId, completionHandler: completionHandler)
            return
        }

        if action == "lock_apps" || action == "unlock_apps" {
            if application.applicationState == .active {
                print("AppDelegate: App is active, forwarding lock/unlock request to Flutter engine")
                super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
                return
            }
            if #available(iOS 16.0, *) {
                let tokens = parseTokensFromPayload(userInfo)
                if !tokens.isEmpty {
                    if action == "lock_apps" {
                        let merged = Array(Set(ScreenTimeManager.shared.getLockedIds() + tokens))
                        ScreenTimeManager.shared.applyShields(ids: merged)
                    } else {
                        let filtered = ScreenTimeManager.shared.getLockedIds().filter { !tokens.contains($0) }
                        ScreenTimeManager.shared.applyShields(ids: filtered)
                    }
                    completionHandler(.newData)
                    return
                }
            }
            completionHandler(.newData)
            return
        }

        if type == "SYNC_LOCKED_APPS" {
            if application.applicationState == .active {
                print("AppDelegate: App is active, forwarding SYNC_LOCKED_APPS to Flutter engine")
                super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
                return
            }
            if #available(iOS 16.0, *) {
                let tokens = parseTokensFromPayload(userInfo)
                if !tokens.isEmpty {
                    ScreenTimeManager.shared.applyShields(ids: tokens)
                    completionHandler(.newData)
                    return
                }
            }
            completionHandler(.newData)
            return
        }

        super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
    }

    // MARK: - handleNativeDataSync (Optimizations 1, 2, 3, 4, 5)
    //
    // Flow:
    //   1. Read credentials + cached values (one synchronize() after reads)
    //   2. If location is stale (>15 min) and network is available → try fresh GPS (5s timeout)
    //   3. Build payloads and POST sequentially: device-info → location → app-usage
    //   Each call gets an 8s timeout. Total budget: 25s (5s stale-loc + 8+8+8 = 21+4 buffer).

    private func handleNativeDataSync(
        pushPayloadChildId: String? = nil,
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard
            let defaults  = sharedDefaults,
            let authToken = defaults.string(forKey: kAuthToken), !authToken.isEmpty
        else {
            print("AppDelegate: handleNativeDataSync — missing auth token, skipping")
            logToExtension("❌ Sync failed: Missing auth token")
            completionHandler(.noData)
            return
        }

        // Prefer App Group stored childId; fall back to push payload child_id/childId
        // (covers first-launch race where syncAppGroupCredentials hasn't run yet)
        let storedChildId = defaults.string(forKey: kChildId)
        guard let childId = (storedChildId?.isEmpty == false ? storedChildId : pushPayloadChildId),
              !childId.isEmpty else {
            print("AppDelegate: handleNativeDataSync — missing child_id (payload+store both empty), skipping")
            logToExtension("❌ Sync failed: Missing childId")
            completionHandler(.noData)
            return
        }
        // If we resolved childId from push payload, persist it for subsequent syncs
        if storedChildId?.isEmpty != false, let pid = pushPayloadChildId {
            defaults.set(pid, forKey: kChildId)
        }

        let apiBase      = defaults.string(forKey: kApiBaseUrl) ?? "https://naviq-server.codescap.com/api/v1/"
        let networkType  = defaults.string(forKey: kNetworkType) ?? "none"
        let locTs        = defaults.double(forKey: kCachedLocTs)
        let locationAge  = Date().timeIntervalSince1970 - locTs

        // Optimization 5: ONE synchronize() after all cached reads, nowhere else
        defaults.synchronize()

        // Optimization 4: stale location check — request fresh GPS if location > 15 min old
        if locationAge > 900 && networkType != "none" {
            print("AppDelegate: 📍 Location is stale (\(Int(locationAge))s) — requesting fresh fix")
            requestFreshLocationWithTimeout(5.0) { [weak self] freshLoc in
                guard let self = self else { return }
                if let fresh = freshLoc {
                    let d = self.sharedDefaults
                    d?.set(fresh.coordinate.latitude,            forKey: self.kCachedLat)
                    d?.set(fresh.coordinate.longitude,           forKey: self.kCachedLng)
                    d?.set(fresh.horizontalAccuracy,             forKey: self.kCachedAcc)
                    d?.set(max(0, fresh.speed),                  forKey: self.kCachedSpd)
                    d?.set(Date().timeIntervalSince1970,         forKey: self.kCachedLocTs)
                    print("AppDelegate: 📍 Fresh location acquired")
                }
                let finalAge = freshLoc != nil ? 0.0 : locationAge
                self.buildAndPostSyncPayload(
                    childId: childId, authToken: authToken, apiBase: apiBase,
                    networkType: networkType, locationAge: finalAge,
                    completionHandler: completionHandler
                )
            }
        } else {
            buildAndPostSyncPayload(
                childId: childId, authToken: authToken, apiBase: apiBase,
                networkType: networkType, locationAge: locationAge,
                completionHandler: completionHandler
            )
        }
    }

    // MARK: - Fresh Location Helper (Optimization 4)

    private func requestFreshLocationWithTimeout(
        _ seconds: Double,
        completion: @escaping (CLLocation?) -> Void
    ) {
        // Fixes a confirmed TestFlight crash (EXC_CRASH/SIGABRT, an uncaught
        // CoreLocation assertion at CLLocationManager.m:1349): this function
        // is reachable from handleNativeDataSync on a push-notification cold
        // launch, a path that never goes through applicationDidBecomeActive
        // — the only place that previously assigned locationManager.delegate
        // and requested authorization (see startLocationServices()). That
        // assignment used to also happen unconditionally at launch before
        // commit b9c90c14 (the UIScene/black-screen fix) deferred it to
        // applicationDidBecomeActive, an unintended side effect on this
        // unrelated path. requestLocation() asserts if called with no
        // delegate set or before authorization is determined — both are true
        // on a first-launch-via-push. Setting the delegate here is
        // idempotent/side-effect-free; skipping the call entirely when not
        // yet authorized preserves the intended feature, since the caller
        // (buildAndPostSyncPayload via handleNativeDataSync) already falls
        // back to the cached/stale location on a nil result.
        locationManager.delegate = self

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            completion(nil)
            return
        }

        var completed = false
        let lock = NSLock()

        // Timeout branch
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            lock.unlock()
            completion(nil)
        }

        // Store completion for use in locationManager(_:didUpdateLocations:)
        pendingFreshLocationCompletion = { loc in
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            lock.unlock()
            completion(loc)
        }

        locationManager.requestLocation()
    }

    // MARK: - buildAndPostSyncPayload (Optimization 2: sequential calls, exact Dart field names)

    private func buildAndPostSyncPayload(
        childId: String,
        authToken: String,
        apiBase: String,
        networkType: String,
        locationAge: Double,
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let defaults = sharedDefaults
        let lat      = defaults?.double(forKey: kCachedLat) ?? 0
        let lng      = defaults?.double(forKey: kCachedLng) ?? 0
        let accuracy = defaults?.double(forKey: kCachedAcc) ?? 0
        let speed    = defaults?.double(forKey: kCachedSpd) ?? 0

        UIDevice.current.isBatteryMonitoringEnabled = true

        // Confirmed false-report incident (iOS only — Android's battery
        // broadcast is available immediately, no equivalent bug there):
        // setting isBatteryMonitoringEnabled = true does not force an
        // instant hardware read. Reading batteryLevel on the very same tick
        // — as this used to do — can return a value the OS cached from
        // before this process was last suspended, since this whole function
        // runs on a background wake from a fully-suspended state (silent
        // push → didReceiveRemoteNotification, main thread). A device sitting
        // suspended for a while could then report a battery level tens of
        // percentage points stale (real case: 70% actual, 40% reported).
        // A short async delay gives the OS a moment to refresh batteryLevel
        // before we read it — negligible against the 25s total sync budget
        // below.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }

            let rawBattery = UIDevice.current.batteryLevel
            let battery    = rawBattery < 0 ? 0 : Int((rawBattery * 100).rounded())
            let isOnline   = networkType != "none"
            let isoNow     = ISO8601DateFormatter().string(from: Date())
            let isStale    = locationAge > 900

            // — Payload 1: Device Status —
            // Field names match Dart _onPostDeviceInfo exactly
            let devicePayload: [String: Any] = [
                "child_id":           childId,
                "battery_percentage": battery,
                "network_type":       networkType,
                "network_status":     isOnline ? "online" : "offline",
                "sound_profile":      "sound",
                "is_online":          isOnline,
                "timestamp":          isoNow
            ]

            // — Payload 2: Location —
            // Field names match Dart _onPostChildLocation exactly.
            // No geocoding: address/place_name are empty strings — server resolves from coords.
            let locationPayload: [String: Any] = [
                "child_id":              childId,
                "lat":                   lat,
                "lng":                   lng,
                "accuracy_m":            accuracy,
                "speed_mps":             speed,
                "bearing":               0.0,
                "address":               "",
                "place_name":            "",
                "is_stale":              isStale,
                "location_age_seconds":  Int(locationAge),
                "timestamp":             isoNow
            ]

            // — Payload 3: Screen Time (only if records exist) —
            // Field names match Dart ScreenTimeSyncService.uploadScreenTimeData exactly
            var usageRecords: [[String: Any]] = []
            if #available(iOS 16.0, *) {
                usageRecords = ScreenTimeManager.shared.getAccumulatedUsage()
            }

            let appsData: [[String: Any]] = usageRecords.map { rec in
                [
                    "packageName": rec["package"]  as? String ?? "",
                    "appName":     rec["appName"]   as? String ?? "",
                    "usageTime":   rec["seconds"]   as? Int    ?? 0,
                    "isSystemApp": false
                ]
            }

            var midnight = Date()
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            var dc = cal.dateComponents([.year, .month, .day], from: Date())
            dc.hour = 0; dc.minute = 0; dc.second = 0
            if let m = cal.date(from: dc) { midnight = m }
            let dateStr = ISO8601DateFormatter().string(from: midnight)

            let screenTimePayload: [String: Any] = [
                "userId":   childId,
                "date":     dateStr,
                "platform": "ios",
                "apps":     appsData
            ]

            // — 25-second safety timeout —
            var didSucceed = false
            let timeoutWork = DispatchWorkItem {
                print("AppDelegate: handleNativeDataSync — 25s timeout reached")
                completionHandler(didSucceed ? .newData : .failed)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeoutWork)

            // — Sequential POST chain (Optimization 2: no concurrent calls) —
            // Each call has an 8-second individual timeout.
            // Order: device-info → location → app-usage (skipped if no records)
            print("AppDelegate: 📤 Starting sequential sync chain")
            self.logToExtension("📤 Dispatching APIs for child=\(childId)")

            self.postJSON(to: "\(apiBase)child/device-status", payload: devicePayload,
                          token: authToken, timeout: 8) { ok in
                if ok { didSucceed = true }
                print("AppDelegate: ✅ device-status ok=\(ok)")
                self.logToExtension(ok ? "✅ device-status OK" : "❌ device-status FAILED")

                self.postJSON(to: "\(apiBase)child/location", payload: locationPayload,
                              token: authToken, timeout: 8) { ok2 in
                    if ok2 { didSucceed = true }
                    print("AppDelegate: ✅ location ok=\(ok2) stale=\(isStale)")
                    self.logToExtension(ok2 ? "✅ location OK (stale=\(isStale))" : "❌ location FAILED")

                    guard !appsData.isEmpty else {
                        timeoutWork.cancel()
                        self.logToExtension("🏁 Sync complete (no app usage)")
                        completionHandler(didSucceed ? .newData : .noData)
                        return
                    }

                    self.postJSON(to: "\(apiBase)app-usage", payload: screenTimePayload,
                                  token: authToken, timeout: 8) { ok3 in
                        if ok3 { didSucceed = true }
                        print("AppDelegate: ✅ app-usage ok=\(ok3) (\(appsData.count) apps)")
                        self.logToExtension(ok3 ? "✅ app-usage OK (\(appsData.count) apps)" : "❌ app-usage FAILED")
                        timeoutWork.cancel()
                        completionHandler(didSucceed ? .newData : .failed)
                    }
                }
            }
        }
    }

    // MARK: - URLSession Helper (Optimization 3: backgroundSession, not URLSession.shared)

    private func postJSON(
        to urlString: String,
        payload: [String: Any],
        token: String,
        timeout: Double = 8,
        completion: @escaping (Bool) -> Void
    ) {
        guard
            let url  = URL(string: urlString),
            let body = try? JSONSerialization.data(withJSONObject: payload)
        else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        // Optimization 3: use backgroundSession, not URLSession.shared
        backgroundSession.dataTask(with: request) { _, response, error in
            if let error = error {
                print("AppDelegate: POST \(urlString) error: \(error.localizedDescription)")
                completion(false)
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(code >= 200 && code < 300)
        }.resume()
    }

    // MARK: - Token Parsing

    private func parseTokensFromPayload(_ userInfo: [AnyHashable: Any]) -> [String] {
        let dataMap = userInfo["data"] as? [String: Any]
        let tokensVal = userInfo["tokens"] ?? dataMap?["tokens"]
        
        if let tokensStr = tokensVal as? String, !tokensStr.isEmpty {
            if let jsonData = tokensStr.data(using: .utf8),
               let parsed  = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
                return parsed
            }
            return tokensStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        if let tokens = tokensVal as? [String] { return tokens }
        return []
    }

    // MARK: - Method Channels

    /// Called by SceneDelegate once the FlutterViewController is ready.
    func setupChannels(controller: FlutterViewController) {
        setupDeviceInfoChannel(controller: controller)
        setupParentalControlChannel(controller: controller)
        setupGeofenceMethodChannel(controller: controller)
    }

    func setupDeviceInfoChannel(controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "com.truenyx.naviq/device_info",
            binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "getSoundProfile": result(self.getSoundProfile())
            case "getInstalledApps": result(self.getInstalledApps())
            case "getBatteryPercentage":
                UIDevice.current.isBatteryMonitoringEnabled = true
                // Same fix as buildAndPostSyncPayload above: batteryLevel isn't
                // guaranteed fresh on the same tick monitoring is enabled — give
                // the OS a moment before reading.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    let rawBattery = UIDevice.current.batteryLevel
                    let battery = rawBattery < 0 ? 0 : Int((rawBattery * 100).rounded())
                    result(battery)
                }
            case "isCharging":
                UIDevice.current.isBatteryMonitoringEnabled = true
                let state = UIDevice.current.batteryState
                let isCharging = state == .charging || state == .full
                result(isCharging)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    func setupParentalControlChannel(controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "com.truenyx.naviq/parental_control",
            binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {

            case "saveAuthToken":
                if let token = call.arguments as? String {
                    self.sharedDefaults?.set(token, forKey: self.kAuthToken)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected string", details: nil))
                }

            case "saveApiBaseUrl":
                if let url = call.arguments as? String {
                    self.sharedDefaults?.set(url, forKey: self.kApiBaseUrl)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected string", details: nil))
                }

            case "saveChildId":
                if let id = call.arguments as? String {
                    self.sharedDefaults?.set(id, forKey: self.kChildId)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected string", details: nil))
                }

            case "getCachedLocation":
                let d: [String: Any?] = [
                    "lat":  self.sharedDefaults?.double(forKey: self.kCachedLat),
                    "lng":  self.sharedDefaults?.double(forKey: self.kCachedLng),
                    "ts":   self.sharedDefaults?.double(forKey: self.kCachedLocTs)
                ]
                result(d)

            case "requestScreenTimePermission":
                self.requestScreenTimePermission(result: result)
            case "checkScreenTimePermission":
                self.checkScreenTimePermission(result: result)
            case "updateLockList":
                if let ids = call.arguments as? [String] {
                    self.updateLockList(ids: ids, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected string array", details: nil))
                }
            case "getScreenTime":
                self.getScreenTimeData(result: result)
            case "getInstalledApps":
                result([])
            case "getAppIcon":
                result(nil)
            case "openFamilyActivityPicker":
                self.openFamilyActivityPicker(result: result)
            case "removeMapping":
                if let id = call.arguments as? String {
                    self.removeMapping(id: id, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected string id", details: nil))
                }
            case "clearAllMappings":
                self.clearAllMappings(result: result)
            case "getMonitoredApps":
                self.getMonitoredApps(result: result)
            case "getDeviceId":
                result(UIDevice.current.identifierForVendor?.uuidString ?? "unknown_ios_device")
            case "setWebFiltering":
                if let enabled = call.arguments as? Bool {
                    self.setWebFiltering(enabled: enabled, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected boolean", details: nil))
                }
            case "getExtensionLogs":
                if #available(iOS 16.0, *) {
                    result(ScreenTimeManager.shared.getExtensionLogs())
                } else {
                    result([])
                }
            case "clearExtensionLogs":
                self.sharedDefaults?.removeObject(forKey: "com.truenyx.naviq.extension_logs")
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func setupGeofenceMethodChannel(controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "com.truenyx.naviq/geofence",
            binaryMessenger: controller.binaryMessenger
        )
        IOSNativeGeofenceManager.shared.methodChannel = channel
        
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "syncGeofences":
                guard let args = call.arguments as? [[String: Any]] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected list of geofences", details: nil))
                    return
                }
                
                var geofences: [NativeGeofence] = []
                for dict in args {
                    if let id = dict["id"] as? String,
                       let name = dict["name"] as? String,
                       let lat = dict["lat"] as? Double,
                       let lng = dict["lng"] as? Double,
                       let radius = dict["radius"] as? Double,
                       let priority = dict["priority"] as? Int {
                        geofences.append(NativeGeofence(id: id, name: name, lat: lat, lng: lng, radius: radius, priority: priority))
                    }
                }
                
                IOSNativeGeofenceManager.shared.syncRegions(with: geofences)
                result(true)
                
            case "fetchGeofences":
                IOSNativeGeofenceManager.shared.fetchGeofencesFromBackend()
                result(true)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Sound Profile

    private func getSoundProfile() -> String {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
        return "sound" // iOS silent switch not readable via public API
    }

    // MARK: - Installed Apps (limited on iOS)

    private func getInstalledApps() -> [[String: Any?]] {
        let known: [(String, String, String)] = [
            ("Settings", "prefs:",   "com.apple.Preferences"),
            ("Safari",   "http://",  "com.apple.mobilesafari"),
            ("Mail",     "mailto:",  "com.apple.mobilemail"),
            ("Messages", "sms:",     "com.apple.MobileSMS"),
            ("Phone",    "tel:",     "com.apple.mobilephone"),
        ]
        return known.compactMap { name, scheme, pkg in
            guard let url = URL(string: scheme),
                  UIApplication.shared.canOpenURL(url) else { return nil }
            return ["packageName": pkg, "appName": name,
                    "iconPath": nil, "isSystemApp": true,
                    "versionName": nil, "versionCode": nil]
        }
    }

    // MARK: - APNs Token

    override func application(_ application: UIApplication,
                              didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        os_log("🔑 APNs Token Registered successfully: %{public}@", log: log, type: .info, tokenString)
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(_ application: UIApplication,
                              didFailToRegisterForRemoteNotificationsWithError error: Error) {
        os_log("❌ Failed to register for remote notifications: %{public}@", log: log, type: .error, error.localizedDescription)
        print("Failed to register for remote notifications: \(error)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    // MARK: - Screen Time Permission

    private func requestScreenTimePermission(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(FlutterError(code: "UNSUPPORTED_OS", message: "iOS 16+ required", details: nil))
            return
        }
        Task { @MainActor in
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                ScreenTimeManager.shared.startMonitoring()
                result(true)
            } catch {
                result(FlutterError(code: "PERMISSION_DENIED", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func checkScreenTimePermission(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else { result(false); return }
        result(AuthorizationCenter.shared.authorizationStatus == .approved)
    }

    private func getScreenTimeData(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else { result([]); return }
        guard AuthorizationCenter.shared.authorizationStatus == .approved else { result([]); return }
        result(ScreenTimeManager.shared.getAccumulatedUsage())
    }

    // MARK: - FamilyActivityPicker

    private func openFamilyActivityPicker(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(FlutterError(code: "UNSUPPORTED_OS", message: "iOS 16.0+ required", details: nil))
            return
        }
        let center = AuthorizationCenter.shared
        if center.authorizationStatus != .approved {
            Task { @MainActor in
                do {
                    try await center.requestAuthorization(for: .individual)
                    self.presentPicker(result: result)
                } catch {
                    result(FlutterError(code: "AUTH_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        } else {
            DispatchQueue.main.async { self.presentPicker(result: result) }
        }
    }

    @available(iOS 16.0, *)
    private func presentPicker(result: @escaping FlutterResult) {
        guard let controller = window?.rootViewController else {
            result(FlutterError(code: "NO_CONTROLLER", message: "Root view controller not found", details: nil))
            return
        }
        let pickerVC = FamilyActivityPickerController()
        pickerVC.onComplete = { tokens in result(tokens) }
        controller.present(pickerVC, animated: true)
    }

    private func removeMapping(id: String, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else { result(false); return }
        let defaults = UserDefaults(suiteName: "group.com.truenyx.naviq")
        
        // 1. Remove from token_map
        if let data = defaults?.data(forKey: "com.truenyx.naviq.token_map"),
           var tokenMap = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            tokenMap.removeValue(forKey: id)
            if let updatedData = try? JSONSerialization.data(withJSONObject: tokenMap) {
                defaults?.set(updatedData, forKey: "com.truenyx.naviq.token_map")
            }
        }
        
        // 2. Remove tokenData key
        defaults?.removeObject(forKey: "token_data_\(id)")
        
        // 3. Remove from selection and re-register
        if let selectionData = defaults?.data(forKey: "com.truenyx.naviq.selection"),
           var selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
            selection.applicationTokens = Set(selection.applicationTokens.filter { "usage_app_\($0.hashValue)" != id })
            selection.categoryTokens = Set(selection.categoryTokens.filter { "usage_cat_\($0.hashValue)" != id })
            ScreenTimeManager.shared.registerSelectedApps(selection: selection)
        }
        
        result(true)
    }

    private func clearAllMappings(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else { result(false); return }
        let defaults = UserDefaults(suiteName: "group.com.truenyx.naviq")
        defaults?.removeObject(forKey: "com.truenyx.naviq.token_map")
        defaults?.removeObject(forKey: "com.truenyx.naviq.selection")
        
        let center = DeviceActivityCenter()
        center.stopMonitoring([DeviceActivityName("com.truenyx.naviq.daily")])
        defaults?.removeObject(forKey: "com.truenyx.naviq.screentime_data")
        
        result(true)
    }

    private func updateLockList(ids: [String], result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else { result(false); return }
        ScreenTimeManager.shared.applyShields(ids: ids)
        result(true)
    }

    private func getMonitoredApps(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else { result([]); return }
        guard let data = sharedDefaults?.data(forKey: "com.truenyx.naviq.token_map"),
              let map  = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            result([]); return
        }
        result(Array(map.values))
    }

    private func setWebFiltering(enabled: Bool, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(FlutterError(code: "UNSUPPORTED_OS", message: "iOS 16+ required", details: nil))
            return
        }
        ScreenTimeManager.shared.applyWebContentFilter(enabled: enabled)
        result(true)
    }
    // MARK: - App Group Logger

    private func logToExtension(_ message: String) {
        guard let defaults = sharedDefaults else { return }
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        var logs = defaults.stringArray(forKey: "com.truenyx.naviq.extension_logs") ?? []
        logs.append("[\(ts)] AppDel: \(message)")
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
        defaults.set(logs, forKey: "com.truenyx.naviq.extension_logs")
    }
}

// MARK: - CLLocationManagerDelegate (Optimization 1: no geocoding, only 5 cache writes)

extension AppDelegate: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        // Optimization 4: consume pending one-shot fresh location request first
        if let pending = pendingFreshLocationCompletion {
            pendingFreshLocationCompletion = nil
            pending(loc)
            return  // Don't double-process this update
        }

        // Write exactly 5 keys — NO CLGeocoder, server derives address from coordinates
        // Optimization 5: no synchronize() here
        let d = sharedDefaults
        d?.set(loc.coordinate.latitude,               forKey: kCachedLat)
        d?.set(loc.coordinate.longitude,              forKey: kCachedLng)
        d?.set(max(0, loc.speed),                     forKey: kCachedSpd)
        d?.set(loc.horizontalAccuracy,                forKey: kCachedAcc)
        d?.set(Date().timeIntervalSince1970,          forKey: kCachedLocTs)

        // Cheap while a normal continuous update is flowing (no-op unless
        // actually drifted past the rearm threshold) — keeps the breadcrumb
        // centered on wherever the device actually is, so it's ready to
        // detect the *next* movement if this update stream itself later goes
        // dark (e.g. the app gets force-quit right after this).
        IOSNativeGeofenceManager.shared.armBreadcrumb(at: loc.coordinate)

        // Trigger background sync if in background with 60-second rate limiting
        if UIApplication.shared.applicationState != .active {
            let now = Date()
            if lastBackgroundSyncTime == nil || now.timeIntervalSince(lastBackgroundSyncTime!) > 60 {
                lastBackgroundSyncTime = now
                os_log("🔄 CoreLocation update triggering native background sync", log: log, type: .info)
                handleNativeDataSync(completionHandler: { _ in })
            }
        }

        // Check geofence dwell status (Fix 1)
        IOSNativeGeofenceManager.shared.checkDwellStatus(currentLocation: loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Consume a pending one-shot completion with nil on error
        if let pending = pendingFreshLocationCompletion {
            pendingFreshLocationCompletion = nil
            pending(nil)
        }
        print("AppDelegate: CLLocationManager error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.startUpdatingLocation()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - Visit Monitoring (Relaunches and updates when user stays/leaves a place)
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude
        let lng = visit.coordinate.longitude
        let ts = visit.arrivalDate.timeIntervalSince1970
        let d = sharedDefaults
        d?.set(lat, forKey: kCachedLat)
        d?.set(lng, forKey: kCachedLng)
        d?.set(0.0, forKey: kCachedSpd)
        d?.set(10.0, forKey: kCachedAcc)
        d?.set(ts, forKey: kCachedLocTs)
        
        os_log("📍 iOS Visit detected: lat=%f, lng=%f", log: log, type: .info, lat, lng)
        logToExtension("📍 Visit detected: \(lat),\(lng)")
        
        if UIApplication.shared.applicationState != .active {
            handleNativeDataSync(completionHandler: { _ in })
        }
    }

    // MARK: - Region Monitoring (Geofence relaunch triggers)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        os_log("📍 Entered region: %{public}@", log: log, type: .info, region.identifier)
        logToExtension("📍 Entered region: \(region.identifier)")
        IOSNativeGeofenceManager.shared.handleEnter(region: region)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        os_log("📍 Exited region: %{public}@", log: log, type: .info, region.identifier)
        logToExtension("📍 Exited region: \(region.identifier)")
        IOSNativeGeofenceManager.shared.handleExit(region: region)
    }
}

// MARK: - ScreenTimeManager

@available(iOS 16.0, *)
class ScreenTimeManager {
    static let shared = ScreenTimeManager()
    private let appGroupID  = "group.com.truenyx.naviq"
    private let usageKey    = "com.truenyx.naviq.screentime_data"
    private let monitorName = DeviceActivityName("com.truenyx.naviq.daily")
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    private init() {}

    private let thresholds = [60, 120, 300, 600, 900, 1800, 3600, 5400, 7200, 10800, 14400, 21600]
    private let maxEvents  = 100

    // MARK: - Monitoring

    func startMonitoring() {
        restoreShieldsIfNeeded()
        restoreWebFilterIfNeeded()

        if let data      = sharedDefaults?.data(forKey: "com.truenyx.naviq.selection"),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            registerSelectedApps(selection: selection)
        } else {
            let center   = DeviceActivityCenter()
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
                intervalEnd:   DateComponents(hour: 23, minute: 59, second: 59),
                repeats: true
            )
            try? center.startMonitoring(monitorName, during: schedule, events: [:])
        }
    }

    func getAccumulatedUsage() -> [[String: Any]] {
        return sharedDefaults?.array(forKey: usageKey) as? [[String: Any]] ?? []
    }

    func registerSelectedApps(selection: FamilyActivitySelection) {
        if let encoded = try? JSONEncoder().encode(selection) {
            sharedDefaults?.set(encoded, forKey: "com.truenyx.naviq.selection")
        }

        let center = DeviceActivityCenter()
        center.stopMonitoring([monitorName])
        sharedDefaults?.removeObject(forKey: usageKey)
        // No synchronize() — removed per Optimization 5

        let totalItems = selection.applicationTokens.count + selection.categoryTokens.count
        var thresholdsToUse = thresholds
        if totalItems > 0 {
            let maxPerItem = max(1, maxEvents / totalItems)
            if maxPerItem < thresholds.count {
                thresholdsToUse = Array(thresholds.prefix(maxPerItem))
            }
        }

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        for token in selection.applicationTokens {
            let hashID = "usage_app_\(token.hashValue)"
            if let tokenData = try? JSONEncoder().encode(token) {
                sharedDefaults?.set(tokenData, forKey: "token_data_\(hashID)")
            }
            for seconds in thresholdsToUse {
                let eventName = DeviceActivityEvent.Name("\(hashID)_\(seconds)")
                events[eventName] = DeviceActivityEvent(applications: [token], threshold: DateComponents(second: seconds))
            }
        }

        for token in selection.categoryTokens {
            let hashID = "usage_cat_\(token.hashValue)"
            if let tokenData = try? JSONEncoder().encode(token) {
                sharedDefaults?.set(tokenData, forKey: "token_data_\(hashID)")
            }
            for seconds in thresholdsToUse {
                let eventName = DeviceActivityEvent.Name("\(hashID)_\(seconds)")
                events[eventName] = DeviceActivityEvent(categories: [token], threshold: DateComponents(second: seconds))
            }
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd:   DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(monitorName, during: schedule, events: events)
            logToExtension("✅ Registered \(events.count) events")
        } catch {
            logToExtension("❌ Registration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Shielding

    private let lockedIdsKey = "com.truenyx.naviq.locked_ids"

    func getLockedIds() -> [String] {
        return sharedDefaults?.stringArray(forKey: lockedIdsKey) ?? []
    }

    func applyShields(ids: [String]) {
        sharedDefaults?.set(ids, forKey: lockedIdsKey)
        // Optimization 5: ONE synchronize() here — shield persistence is critical
        sharedDefaults?.synchronize()

        guard let data      = sharedDefaults?.data(forKey: "com.truenyx.naviq.selection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            print("ScreenTimeManager: No valid selection for shielding")
            return
        }

        let store = ManagedSettingsStore()

        if ids.isEmpty {
            store.shield.applications          = nil
            store.shield.applicationCategories = nil
            logToExtension("🔓 Cleared all shields")
            return
        }

        var tokensToShield     = Set<ApplicationToken>()
        var categoriesToShield = Set<ActivityCategoryToken>()

        for id in ids {
            // Strategy 1: stable JSONEncoder-encoded token (survives reboots)
            if let tokenData = sharedDefaults?.data(forKey: "token_data_\(id)") {
                if id.hasPrefix("usage_app_"),
                   let token = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {
                    tokensToShield.insert(token); continue
                }
                if id.hasPrefix("usage_cat_"),
                   let token = try? JSONDecoder().decode(ActivityCategoryToken.self, from: tokenData) {
                    categoriesToShield.insert(token); continue
                }
            }
            // Strategy 2: fallback — scan selection by hashValue
            if id.hasPrefix("usage_app_") {
                for token in selection.applicationTokens where "usage_app_\(token.hashValue)" == id {
                    tokensToShield.insert(token); break
                }
            } else if id.hasPrefix("usage_cat_") {
                for token in selection.categoryTokens where "usage_cat_\(token.hashValue)" == id {
                    categoriesToShield.insert(token); break
                }
            }
        }

        store.shield.applications          = tokensToShield.isEmpty ? nil : tokensToShield
        store.shield.applicationCategories = categoriesToShield.isEmpty ? nil : .specific(categoriesToShield)
        logToExtension("🔒 Shielded \(tokensToShield.count) apps + \(categoriesToShield.count) categories")
    }

    func restoreShieldsIfNeeded() {
        guard let ids = sharedDefaults?.stringArray(forKey: lockedIdsKey), !ids.isEmpty else { return }
        applyShields(ids: ids)
    }

    func clearShields() {
        sharedDefaults?.removeObject(forKey: lockedIdsKey)
        let store = ManagedSettingsStore()
        store.shield.applications          = nil
        store.shield.applicationCategories = nil
    }

    // MARK: - Web Content Filter

    private let webFilterKey = "com.truenyx.naviq.web_filter_enabled"

    // Apple's public ManagedSettings API only exposes an explicit domain
    // blocklist (WebContentSettings.FilterPolicy.specific) — there is no
    // category-based "block adult content" policy available to 3rd-party
    // apps (that auto-filter is Apple's own Screen Time-only feature, not
    // programmatically settable). So this list can never be "complete" — it
    // only covers named domains, not arbitrary/new/mirror sites — but a
    // larger, curated list of well-known adult domains is meaningfully
    // better than a handful, at essentially no runtime cost.
    private static let blockedAdultDomains: Set<WebDomain> = Set([
        "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com",
        "youporn.com", "tube8.com", "spankbang.com", "xxx.com", "porn.com",
        "brazzers.com", "onlyfans.com", "chaturbate.com", "livejasmin.com",
        "myfreecams.com", "camsoda.com", "stripchat.com", "bongacams.com",
        "tnaflix.com", "motherless.com", "rule34.xxx", "e-hentai.org",
        "nhentai.net", "thumbzilla.com", "beeg.com", "txxx.com", "hclips.com",
        "drtuber.com", "sunporno.com", "porntrex.com", "eporner.com",
        "xtube.com", "adultfriendfinder.com", "ashleymadison.com",
        "literotica.com", "hqporner.com", "pornone.com", "3movs.com",
        "javhd.com", "fapdu.com", "keezmovies.com", "extremetube.com",
        "4tube.com", "vporn.com", "camwhores.tv", "fetlife.com",
    ].map { WebDomain(domain: $0) })

    func applyWebContentFilter(enabled: Bool) {
        sharedDefaults?.set(enabled, forKey: webFilterKey)
        // No synchronize() — removed per Optimization 5
        let store = ManagedSettingsStore()
        if enabled {
            store.webContent.blockedByFilter = .specific(Self.blockedAdultDomains)
            logToExtension("🚫 Web filter enabled (\(Self.blockedAdultDomains.count) domains)")
        } else {
            store.webContent.blockedByFilter = nil
            logToExtension("🔓 Web filter disabled")
        }
    }

    func restoreWebFilterIfNeeded() {
        let enabled = sharedDefaults?.bool(forKey: webFilterKey) ?? false
        if enabled { applyWebContentFilter(enabled: true) }
    }

    // MARK: - Logging

    private func logToExtension(_ message: String) {
        guard let defaults = sharedDefaults else { return }
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        var logs = defaults.stringArray(forKey: "com.truenyx.naviq.extension_logs") ?? []
        logs.append("[\(ts)] Runner: \(message)")
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
        defaults.set(logs, forKey: "com.truenyx.naviq.extension_logs")
    }

    func getExtensionLogs() -> [String] {
        return sharedDefaults?.stringArray(forKey: "com.truenyx.naviq.extension_logs") ?? ["No logs found"]
    }
}

// MARK: - FamilyActivityPicker SwiftUI Wrapper

@available(iOS 16.0, *)
struct FamilyActivityPickerView: View {
    @Binding var selection: FamilyActivitySelection
    @Binding var isPresented: Bool
    var onConfirm: (FamilyActivitySelection) -> Void

    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Select Apps to Monitor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { isPresented = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { onConfirm(selection); isPresented = false }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}

@available(iOS 16.0, *)
class FamilyActivityPickerController: UIViewController {
    private var selection = FamilyActivitySelection()
    var onComplete: (([[String: Any]]) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let isPresented   = Binding<Bool>(get: { true }, set: { [weak self] shown in if !shown { self?.dismiss(animated: true) } })
        let selectionBind = Binding<FamilyActivitySelection>(get: { self.selection }, set: { self.selection = $0 })

        let hostingVC = UIHostingController(rootView: AnyView(
            FamilyActivityPickerView(
                selection: selectionBind,
                isPresented: isPresented,
                onConfirm: { [weak self] final in self?.handleSelection(final) }
            )
        ))
        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingVC.didMove(toParent: self)
    }

    // MARK: - Selection Handling

    private func handleSelection(_ selection: FamilyActivitySelection) {
        let appTokens = Array(selection.applicationTokens)
        let catTokens = Array(selection.categoryTokens)
        PickerLogger.log("handleSelection — \(appTokens.count) application tokens, \(catTokens.count) category tokens")

        // Batch-resolve ALL app names in one off-screen render + single RunLoop wait.
        // ApplicationToken names require async XPC to SpringBoard; without this wait
        // all extraction stages return nil and we get "App (102835)" fallbacks.
        let resolvedNames = Self.batchResolveAppNames(appTokens)

        var selectedItems: [[String: Any]] = []

        // ── Applications (primary — always preferred over categories) ──────────
        for (i, token) in appTokens.enumerated() {
            let hashID    = "usage_app_\(token.hashValue)"
            let resolved  = resolvedNames[i]
            let finalName = resolved ?? "App (\(String(hashID.suffix(6))))"
            let bundleId  = Self.extractBundleId(token)
            let entry: [String: Any] = [
                "id":          hashID,
                "type":        "application",
                "displayName": finalName,
                "bundleId":    bundleId,
                "selectedAt":  Int(Date().timeIntervalSince1970)
            ]
            selectedItems.append(entry)
            PickerLogger.logApp(hashID: hashID, name: finalName, bundleId: bundleId,
                                usedFallback: resolved == nil)
        }

        // ── Categories (secondary / fallback) ─────────────────────────────────
        for token in catTokens {
            let hashID   = "usage_cat_\(token.hashValue)"
            let raw      = Self.resolveCategoryName(token: token)
            let safe     = Self.sanitizeCategoryName(raw: raw, hashID: hashID)
            let entry: [String: Any] = [
                "id":          hashID,
                "type":        "category",
                "displayName": safe,
                "bundleId":    "",
                "selectedAt":  Int(Date().timeIntervalSince1970)
            ]
            selectedItems.append(entry)
            PickerLogger.logCategory(hashID: hashID, rawName: raw, finalName: safe)
        }

        // ── Persist token_map to App Group UserDefaults ────────────────────────
        let defaults = UserDefaults(suiteName: "group.com.truenyx.naviq")
        var tokenMap: [String: [String: Any]] = [:]
        
        if let existingMapData = defaults?.data(forKey: "com.truenyx.naviq.token_map"),
           let existingMap = try? JSONSerialization.jsonObject(with: existingMapData) as? [String: [String: Any]] {
            tokenMap = existingMap
        }
        
        for item in selectedItems {
            if let id = item["id"] as? String { tokenMap[id] = item }
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: tokenMap) {
            defaults?.set(data, forKey: "com.truenyx.naviq.token_map")
            PickerLogger.log("token_map written — \(tokenMap.count) entries")
        } else {
            PickerLogger.log("⚠️ token_map serialization FAILED")
        }

        var combinedSelection = selection
        if let selectionData = defaults?.data(forKey: "com.truenyx.naviq.selection"),
           let existingSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
            combinedSelection.applicationTokens.formUnion(existingSelection.applicationTokens)
            combinedSelection.categoryTokens.formUnion(existingSelection.categoryTokens)
            combinedSelection.webDomainTokens.formUnion(existingSelection.webDomainTokens)
        }
        
        ScreenTimeManager.shared.registerSelectedApps(selection: combinedSelection)
        onComplete?(selectedItems)
    }

    // MARK: - Batch App Name Resolution
    // Renders ALL token labels simultaneously in one off-screen container,
    // then pays the RunLoop wait ONCE for all tokens combined.
    // This is the correct production approach for FamilyControls ApplicationToken:
    // names are populated asynchronously via XPC to SpringBoard, so a
    // RunLoop.main.run(until:) wait is mandatory — CATransaction.flush() alone
    // does not trigger that XPC resolution.

    private static func batchResolveAppNames(_ tokens: [ApplicationToken]) -> [String?] {
        guard !tokens.isEmpty else { return [] }

        // Build one container VC hosting a child VC per token.
        // Children are stacked vertically so each label is in its own isolated subtree.
        let rowH: CGFloat     = 50
        let totalH: CGFloat   = rowH * CGFloat(tokens.count) + 8
        let containerVC       = UIViewController()
        containerVC.view.frame = CGRect(x: 0, y: 0, width: 320, height: totalH)
        containerVC.view.backgroundColor = UIColor.clear

        let window = UIWindow(frame: containerVC.view.frame)
        window.rootViewController = containerVC
        window.isHidden = false

        var childVCs: [UIHostingController<AnyView>] = []
        for (i, token) in tokens.enumerated() {
            let labelView = AnyView(
                Label(token)
                    .labelStyle(.titleOnly)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            let vc = UIHostingController(rootView: labelView)
            vc.view.frame = CGRect(x: 4,
                                   y: CGFloat(i) * rowH + 4,
                                   width: 312,
                                   height: rowH)
            vc.view.backgroundColor = UIColor.clear
            containerVC.addChild(vc)
            containerVC.view.addSubview(vc.view)
            vc.didMove(toParent: containerVC)
            childVCs.append(vc)
        }

        // First layout pass
        containerVC.view.setNeedsLayout()
        containerVC.view.layoutIfNeeded()
        for vc in childVCs { vc.view.setNeedsLayout(); vc.view.layoutIfNeeded() }
        CATransaction.flush()

        // KEY WAIT: FamilyControls resolves ApplicationToken display names
        // via an async XPC call to SpringBoard. Without this RunLoop wait,
        // every extraction stage returns empty/nil and all apps show as fallbacks.
        PickerLogger.log("[Batch] Starting 1.5s async wait for \(tokens.count) token(s)…")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))

        // Second layout pass — forces SwiftUI to apply the now-available names
        for vc in childVCs { vc.view.setNeedsLayout(); vc.view.layoutIfNeeded() }
        CATransaction.flush()

        // Extract one name per child VC (each subtree contains exactly one token label)
        let results: [String?] = childVCs.map { vc in
            findText(in: vc.view)
        }

        let resolvedSummary = results.enumerated()
            .map { idx, name in "[\(idx)]\(name ?? "nil")" }
            .joined(separator: " ")
        PickerLogger.log("[Batch] Resolved: \(resolvedSummary)")

        // Teardown
        for vc in childVCs {
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
        }
        window.isHidden = true
        window.rootViewController = nil
        return results
    }

    // MARK: - Application Token Name Resolution (single-token fallback pipeline)
    // Used only when batchResolveAppNames is not applicable (e.g. category tokens).
    // Stage 1: SwiftUI Label render via off-screen UIWindow + RunLoop wait
    // Stage 2: JSON/Codable key scan
    // Stage 3: Mirror reflection

    private static func resolveAppName(token: ApplicationToken) -> String? {
        // Stage 1 — includes RunLoop wait (same mechanism as batchResolveAppNames)
        if let n = extractNameViaWindow(AnyView(Label(token).labelStyle(.titleOnly))),
           !n.isEmpty, !isGenericCategoryLabel(n) { return n }
        // Stage 2
        if let n = extractNameViaCodable(token), !isGenericCategoryLabel(n) { return n }
        // Stage 3
        if let n = extractNameViaMirror(token), !isGenericCategoryLabel(n) { return n }
        return nil
    }

    // MARK: - Category Token Name Resolution + Validation

    private static func resolveCategoryName(token: ActivityCategoryToken) -> String? {
        // Stage 1
        if let n = extractNameViaWindow(AnyView(Label(token).labelStyle(.titleOnly))),
           !n.isEmpty { return n }
        // Stage 2
        if let n = extractNameViaCodable(token) { return n }
        // Stage 3
        if let n = extractNameViaMirror(token) { return n }
        return nil
    }

    /// Validates and sanitises a category name.
    /// Returns the cleaned name when valid, or a safe generic fallback.
    private static func sanitizeCategoryName(raw: String?, hashID: String) -> String {
        guard let name = raw, !name.isEmpty else {
            PickerLogger.log("⚠️ [Cat] \(hashID) — nil/empty label → using 'App Category'")
            return "App Category"
        }
        if isGenericCategoryLabel(name) {
            PickerLogger.log("⚠️ [Cat] \(hashID) — rejected generic label '\(name)' → using 'App Category'")
            return "App Category"
        }
        return name
    }

    // MARK: - Generic Label Detector
    // Returns true when a string is a known Apple placeholder that must NOT be stored.

    private static func isGenericCategoryLabel(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        // Empty or purely numeric
        if t.isEmpty { return true }
        if t.rangeOfCharacter(from: .letters) == nil { return true }
        // Exact system placeholders
        let exact = ["Category", "App", "Application", "Label", "Image",
                     "Button", "View", "Text", "Unknown"]
        if exact.contains(t) { return true }
        // "Category N", "Category 3", "Category 12" patterns
        if t.hasPrefix("Category ") {
            let suffix = t.dropFirst("Category ".count)
            if suffix.rangeOfCharacter(from: CharacterSet.letters.inverted) == nil
                || Int(suffix) != nil { return true }
            // Any "Category <word>" without spaces that is just one short word is likely generic
            if !suffix.contains(" ") && suffix.count <= 4 { return true }
        }
        // "App N" patterns
        if t.hasPrefix("App "), let suffix = Int(t.dropFirst("App ".count)) {
            let _ = suffix; return true
        }
        return false
    }

    // MARK: - Bundle ID Extraction (best-effort, sandboxed on iOS)

    private static func extractBundleId(_ token: ApplicationToken) -> String {
        guard let data = try? JSONEncoder().encode(token),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        for key in ["bundleIdentifier", "bundleId", "identifier"] {
            if let bid = json[key] as? String, !bid.isEmpty { return bid }
        }
        return ""
    }

    // MARK: - Name Extraction Helpers

    /// Single-token off-screen render with the mandatory RunLoop wait.
    /// Used for category tokens and as a per-token fallback.
    /// For application tokens use batchResolveAppNames (more efficient).
    private static func extractNameViaWindow(_ swiftUIView: AnyView) -> String? {
        let hostingVC = UIHostingController(rootView: swiftUIView)
        let window    = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
        window.rootViewController = hostingVC
        window.isHidden = false

        // Initial layout pass
        hostingVC.view.setNeedsLayout()
        hostingVC.view.layoutIfNeeded()
        CATransaction.flush()

        // FamilyControls resolves token display names via async XPC to SpringBoard.
        // RunLoop.main.run(until:) is required to let that resolution complete.
        // CATransaction.flush() alone is not sufficient.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))

        // Second layout pass after async resolution
        hostingVC.view.setNeedsLayout()
        hostingVC.view.layoutIfNeeded()
        CATransaction.flush()

        let result = findText(in: hostingVC.view)
        window.isHidden = true
        window.rootViewController = nil
        return result
    }

    /// Walk the entire UIKit view subtree and return the first valid display name string.
    /// Prefers accessibilityLabel (set by FamilyControls after XPC resolution) over UILabel.text.
    private static func findText(in view: UIView) -> String? {
        // FamilyControls sets accessibilityLabel to the resolved app name
        if let label = view.accessibilityLabel,
           isValidDisplayName(label),
           !isGenericCategoryLabel(label) { return label }
        // UILabel direct text (secondary path)
        if let lbl = view as? UILabel,
           let text = lbl.text,
           isValidDisplayName(text),
           !isGenericCategoryLabel(text) { return text }
        for sub in view.subviews {
            if let found = findText(in: sub) { return found }
        }
        return nil
    }

    /// Validates that a candidate string is a plausible display name.
    /// Does NOT reject category-style names here — `isGenericCategoryLabel` handles that separately.
    private static func isValidDisplayName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 && t.count <= 60 else { return false }
        guard t.rangeOfCharacter(from: .letters) != nil else { return false }
        // Reject raw SwiftUI element type names surfaced by accessibility
        let uiElements = ["Label", "Image", "Button", "View", "Text",
                          "HStack", "VStack", "ZStack", "ScrollView"]
        return !uiElements.contains(t)
    }

    private static func extractNameViaCodable<T: Encodable>(_ token: T) -> String? {
        guard let data = try? JSONEncoder().encode(token),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        // Key priority: human-readable name first, identifiers last
        for key in ["name", "displayName", "localizedDisplayName", "localizedName",
                    "title", "label", "rawValue", "identifier"] {
            if let name = json[key] as? String, isValidDisplayName(name) { return name }
        }
        return nil
    }

    private static func extractNameViaMirror(_ token: Any) -> String? {
        let mirror = Mirror(reflecting: token)
        for child in mirror.children {
            if let s = child.value as? String, isValidDisplayName(s) { return s }
            // One level deep
            for ic in Mirror(reflecting: child.value).children {
                if let s = ic.value as? String, isValidDisplayName(s) { return s }
            }
        }
        return nil
    }
}

// MARK: - Picker Diagnostic Logger
// Structured log lines visible in Xcode console + App Group shared logs.

@available(iOS 16.0, *)
private enum PickerLogger {
    private static let prefix = "[Picker]"

    static func log(_ message: String) {
        print("\(prefix) \(message)")
        writeToShared(message)
    }

    static func logApp(hashID: String, name: String, bundleId: String, usedFallback: Bool) {
        let fallbackNote = usedFallback ? " ⚠️ FALLBACK" : ""
        let line = "✅ [App]  hash=\(hashID)  name=\(name)  bundle=\(bundleId.isEmpty ? "(unknown)" : bundleId)\(fallbackNote)"
        print("\(prefix) \(line)")
        writeToShared(line)
    }

    static func logCategory(hashID: String, rawName: String?, finalName: String) {
        let wasRejected = rawName.map { $0 != finalName } ?? true   // nil rawName is always a rejection
        let rawDisplay  = rawName ?? "nil"
        let rejection   = wasRejected ? "  ⚠️ raw='\(rawDisplay)' REJECTED" : ""
        let line = "🏷️ [Cat]  hash=\(hashID)  name=\(finalName)\(rejection)"
        print("\(prefix) \(line)")
        writeToShared(line)
    }

    private static func writeToShared(_ message: String) {
        guard let defaults = UserDefaults(suiteName: "group.com.truenyx.naviq") else { return }
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        var logs = defaults.stringArray(forKey: "com.truenyx.naviq.extension_logs") ?? []
        logs.append("[\(ts)] Picker: \(message)")
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        defaults.set(logs, forKey: "com.truenyx.naviq.extension_logs")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate {
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let dataMap = userInfo["data"] as? [String: Any]
        let type = userInfo["type"] as? String ?? dataMap?["type"] as? String ?? (userInfo["gcm.notification.type"] as? String)
        let action = userInfo["action"] as? String ?? dataMap?["action"] as? String
        
        os_log("🔔 Notification Will Present (foreground): type=%{public}@, action=%{public}@", log: log, type: .info, type ?? "nil", action ?? "nil")
        logToExtension("🔔 Notification Will Present (foreground): type=\(type ?? "nil") action=\(action ?? "nil")")
        
        if #available(iOS 16.0, *) { handleLockPayloadIfNeeded(userInfo) }
        completionHandler([.banner, .badge, .sound])
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let dataMap = userInfo["data"] as? [String: Any]
        let type = userInfo["type"] as? String ?? dataMap?["type"] as? String ?? (userInfo["gcm.notification.type"] as? String)
        let action = userInfo["action"] as? String ?? dataMap?["action"] as? String
        
        os_log("👉 Notification Tapped (App Open): type=%{public}@, action=%{public}@", log: log, type: .info, type ?? "nil", action ?? "nil")
        logToExtension("👉 Notification Tapped (App Open): type=\(type ?? "nil") action=\(action ?? "nil")")
        
        if #available(iOS 16.0, *) { handleLockPayloadIfNeeded(userInfo) }
        completionHandler()
    }

    @available(iOS 16.0, *)
    private func handleLockPayloadIfNeeded(_ userInfo: [AnyHashable: Any]) {
        let type   = userInfo["type"]   as? String ?? (userInfo["gcm.notification.type"] as? String)
        let action = userInfo["action"] as? String
        let tokens = parseTokensFromPayload(userInfo)
        guard !tokens.isEmpty else { return }

        if action == "lock_apps" {
            let merged = Array(Set(ScreenTimeManager.shared.getLockedIds() + tokens))
            ScreenTimeManager.shared.applyShields(ids: merged)
        } else if action == "unlock_apps" {
            let filtered = ScreenTimeManager.shared.getLockedIds().filter { !tokens.contains($0) }
            ScreenTimeManager.shared.applyShields(ids: filtered)
        } else if type == "SYNC_LOCKED_APPS" {
            ScreenTimeManager.shared.applyShields(ids: tokens)
        }
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("Firebase registration token: \(String(describing: fcmToken))")
        NotificationCenter.default.post(
            name: Notification.Name("FCMToken"),
            object: nil,
            userInfo: ["token": fcmToken ?? ""]
        )
    }
}
