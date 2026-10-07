import Foundation
import CoreLocation
import os.log
import Flutter
import UIKit

// MARK: - Geofence Model
struct NativeGeofence: Codable, Equatable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let radius: Double
    let priority: Int // 1=Home, 2=School, 3=Current Destination, 4=Frequently Visited, 5=Remaining Places
}

// MARK: - Geofence Event
struct GeofenceEvent: Codable {
    let type: String // "ENTER" | "EXIT" | "DWELL"
    let geofenceId: String
    let timestamp: String
    let lat: Double
    let lng: Double
}

// MARK: - Geofence Api Config
struct GeofenceApiConfig: Codable {
    var syncEndpoint: String = "child/geofence-event"
    var fetchEndpoint: String = "child/geofences"
    var isSyncEnabled: Bool = true
    var isGetReachable: Bool = false
    var isPostReachable: Bool = false
}

// MARK: - Native Geofence Manager
class IOSNativeGeofenceManager: NSObject {
    static let shared = IOSNativeGeofenceManager()
    
    private let log = OSLog(subsystem: "com.truenyx.naviq", category: "IOSNativeGeofenceManager")
    private let appGroupID = "group.com.truenyx.naviq"
    private let kGeofencesKey = "com.truenyx.naviq.geofences"
    private let kLastSyncTimeKey = "com.truenyx.naviq.geofences_last_sync"
    private let kApiConfigKey = "com.truenyx.naviq.api_config"
    private let kBreadcrumbLatKey = "com.truenyx.naviq.breadcrumb_lat"
    private let kBreadcrumbLngKey = "com.truenyx.naviq.breadcrumb_lng"

    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    private var locationManager: CLLocationManager?

    /// Flutter method channel to forward events when app is active
    var methodChannel: FlutterMethodChannel?

    /// Called when the breadcrumb region (not a parent-defined geofence) is
    /// entered/exited — the app's own signal that the device has moved a
    /// meaningful distance while it may have had no other way to wake up.
    /// AppDelegate wires this to handleNativeDataSync + re-arming the
    /// breadcrumb at the new position.
    var onBreadcrumbCrossed: ((CLLocationCoordinate2D) -> Void)?

    /// Called after a parent-defined geofence ENTER/EXIT region callback has
    /// been recorded/posted. A region callback is only a HINT — the server
    /// confirms it from RELIABLE, FRESH location points — so AppDelegate uses
    /// this to take and post fresh accurate fixes right away instead of
    /// waiting for the next routine update.
    var onGeofenceRegionCrossed: ((String) -> Void)?

    // MARK: - Breadcrumb Region (force-quit tracking backstop)
    //
    // Standard continuous location updates (startUpdatingLocation) and
    // significant-location-change monitoring both go silent once the user
    // force-quits the app from the app switcher — confirmed via a real
    // device's bg_log on 2026-08-12: after AppLifecycleState.detached, the
    // app produced zero location data for ~5.5 hours despite the child
    // actually driving a 24-minute, 4.4km trip during that window. Region
    // monitoring is one of the few mechanisms whose relaunch is driven by
    // iOS's own locationd daemon rather than the app process, and it's
    // observed to survive force-quit far more reliably in practice than SLC.
    //
    // This isn't a parent-configured geofence — it's a single circle the app
    // manages for itself, always centered on the last known position, purely
    // so that "the device moved" is itself detectable (didExitRegion) even
    // with the Dart engine and native continuous updates both dead. On every
    // crossing, AppDelegate posts a fresh fix and this re-arms a new circle
    // around the new position — cascading breadcrumbs instead of one static
    // fence.
    let breadcrumbIdentifier = "com.truenyx.naviq.breadcrumb"
    /// Deliberately wider than a parent geofence's typical radius — this
    /// exists to detect "moved at all while dead", not to be a precise
    /// safe-place boundary, and too tight a radius against normal GPS
    /// jitter (parked car, indoors) would burn the exit/re-arm cycle
    /// (and a monitored-region slot swap) on noise instead of real movement.
    private let breadcrumbRadius: CLLocationDistance = 300
    /// Only re-arm from a continuous-update tick (not an exit event, which
    /// always re-arms) once actually drifted away from the current circle —
    /// otherwise every single foreground/background location callback would
    /// tear down and recreate the same region.
    private let breadcrumbRearmThreshold: CLLocationDistance = 150

    private func getBreadcrumbCenter() -> CLLocationCoordinate2D? {
        guard let defaults = sharedDefaults,
              defaults.object(forKey: kBreadcrumbLatKey) != nil else { return nil }
        return CLLocationCoordinate2D(
            latitude: defaults.double(forKey: kBreadcrumbLatKey),
            longitude: defaults.double(forKey: kBreadcrumbLngKey)
        )
    }

    /// (Re)centers the breadcrumb circle on `coordinate`, replacing whatever
    /// was previously monitored under `breadcrumbIdentifier`. Safe to call
    /// often — it's a no-op once already centered within the rearm threshold.
    func armBreadcrumb(at coordinate: CLLocationCoordinate2D, force: Bool = false) {
        guard let manager = locationManager else { return }

        if !force, let current = getBreadcrumbCenter() {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            if distance < breadcrumbRearmThreshold {
                return
            }
        }

        if let existing = manager.monitoredRegions.first(where: { $0.identifier == breadcrumbIdentifier }) {
            manager.stopMonitoring(for: existing)
        }

        let radius = min(breadcrumbRadius, manager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: coordinate, radius: radius, identifier: breadcrumbIdentifier)
        region.notifyOnEntry = false
        region.notifyOnExit = true
        manager.startMonitoring(for: region)

        sharedDefaults?.set(coordinate.latitude, forKey: kBreadcrumbLatKey)
        sharedDefaults?.set(coordinate.longitude, forKey: kBreadcrumbLngKey)

        os_log("🍞 [Breadcrumb] Armed at %f,%f (radius %f)", log: self.log, type: .info, coordinate.latitude, coordinate.longitude, radius)
    }

    /// True for the reserved breadcrumb region, so callers that iterate
    /// `monitoredRegions` (or route didEnter/didExitRegion) can tell it apart
    /// from a parent-defined geofence without string-matching everywhere.
    func isBreadcrumb(_ identifier: String) -> Bool {
        identifier == breadcrumbIdentifier
    }
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    func initialize(locationManager: CLLocationManager) {
        self.locationManager = locationManager
        restoreRegions()
        verifyAndRepairRegions()
        checkForPeriodicSync()
        runApiDiagnostics()
    }
    
    @objc private func appWillEnterForeground() {
        verifyAndRepairRegions()
        runApiDiagnostics()
    }
    
    func getGeofences() -> [NativeGeofence] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: kGeofencesKey),
              let list = try? JSONDecoder().decode([NativeGeofence].self, from: data) else {
            return []
        }
        return list
    }
    
    func persistGeofences(_ list: [NativeGeofence]) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: kGeofencesKey)
        defaults.synchronize()
    }
    
    func getApiConfig() -> GeofenceApiConfig {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: kApiConfigKey),
              let config = try? JSONDecoder().decode(GeofenceApiConfig.self, from: data) else {
            return GeofenceApiConfig()
        }
        return config
    }
    
    func persistApiConfig(_ config: GeofenceApiConfig) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: kApiConfigKey)
        defaults.synchronize()
    }
    
    /// Synchronize monitored regions with Apple's 20 geofence limit and prioritization
    func syncRegions(with newGeofences: [NativeGeofence]) {
        guard let manager = locationManager else { return }
        
        let sorted = newGeofences.sorted { (g1, g2) -> Bool in
            if g1.priority != g2.priority {
                return g1.priority < g2.priority
            }
            return g1.id < g2.id
        }
        
        // Apple caps monitored regions at 20 total per app — reserve one slot
        // for the breadcrumb circle (see armBreadcrumb) so a family with a
        // full 20 parent geofences doesn't silently starve the force-quit
        // tracking backstop of a slot.
        let selected = Array(sorted.prefix(19))
        persistGeofences(selected)

        let currentMonitored = manager.monitoredRegions
        for region in currentMonitored {
            guard let circularRegion = region as? CLCircularRegion else { continue }
            if isBreadcrumb(circularRegion.identifier) { continue }
            if !selected.contains(where: { $0.id == circularRegion.identifier }) {
                manager.stopMonitoring(for: circularRegion)
                os_log("📍 [NativeGeofence] Unregistered geofence: %{public}@", log: self.log, type: .info, circularRegion.identifier)
                notifyFlutterUnregistered(geofenceId: circularRegion.identifier)
            }
        }
        
        for fence in selected {
            let radius = min(fence.radius, manager.maximumRegionMonitoringDistance)
            let center = CLLocationCoordinate2D(latitude: fence.lat, longitude: fence.lng)
            
            let region = CLCircularRegion(center: center, radius: radius, identifier: fence.id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            
            manager.startMonitoring(for: region)
            os_log("📍 [NativeGeofence] Registered geofence: %{public}@ (Radius: %f)", log: self.log, type: .info, fence.id, radius)
            notifyFlutterRegistered(geofenceId: fence.id)
        }
    }
    
    /// Restore registered regions upon relaunch or device reboot
    func restoreRegions() {
        guard let manager = locationManager else { return }
        let currentGeofences = getGeofences()
        let currentMonitored = manager.monitoredRegions

        // Monitored regions normally survive relaunch at the OS level, but a
        // reinstall or an iOS-level region eviction can drop it silently —
        // re-arm from the last persisted center (or do nothing if the
        // breadcrumb has genuinely never been armed yet; the first real
        // location fix elsewhere in AppDelegate arms it).
        if !currentMonitored.contains(where: { isBreadcrumb($0.identifier) }),
           let lastCenter = getBreadcrumbCenter() {
            armBreadcrumb(at: lastCenter, force: true)
        }

        for fence in currentGeofences {
            let isMonitored = currentMonitored.contains { $0.identifier == fence.id }
            if !isMonitored {
                let radius = min(fence.radius, manager.maximumRegionMonitoringDistance)
                let center = CLLocationCoordinate2D(latitude: fence.lat, longitude: fence.lng)
                
                let region = CLCircularRegion(center: center, radius: radius, identifier: fence.id)
                region.notifyOnEntry = true
                region.notifyOnExit = true
                
                manager.startMonitoring(for: region)
                os_log("📍 [NativeGeofence] Restored geofence monitoring: %{public}@", log: self.log, type: .info, fence.id)
            }
        }
    }
    
    // MARK: - Region Audit & Repair (Fix 3)
    func verifyAndRepairRegions() {
        guard let manager = locationManager else { return }
        let persisted = getGeofences()
        let audit = RegionHealthMonitor.shared.auditRegions(manager: manager, persisted: persisted)
        
        if !audit.isHealthy {
            os_log("🛠️ [RegionHealth] Health audit failed. Attempting region restoration...", log: log, type: .info)
            restoreRegions()
        }
    }
    
    // MARK: - Event Handlers
    func handleEnter(region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        if isBreadcrumb(circularRegion.identifier) { return } // notifyOnEntry is false, but guard defensively
        os_log("📍 [NativeGeofence] ENTER geofence: %{public}@", log: self.log, type: .info, circularRegion.identifier)
        
        // Save enter event
        processEvent(geofenceId: circularRegion.identifier, type: "ENTER", coordinate: circularRegion.center)
        onGeofenceRegionCrossed?("region_enter")
        
        // Persist enter timestamp for non-timer dwell detection (Fix 1)
        if let defaults = sharedDefaults {
            defaults.set(Date().timeIntervalSince1970, forKey: "enterTimestamp_\(circularRegion.identifier)")
            defaults.set(false, forKey: "dwellFired_\(circularRegion.identifier)")
            defaults.synchronize()
        }
    }
    
    func handleExit(region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        if isBreadcrumb(circularRegion.identifier) {
            // Not a parent geofence event — this is purely "the device moved
            // while it may have had no other way to tell us". Hand off to
            // AppDelegate to grab a fresh fix, post it, and re-arm the
            // breadcrumb at the new position; don't run it through
            // processEvent (that's the parent-facing ENTER/EXIT/DWELL feed).
            os_log("🍞 [Breadcrumb] EXIT — device moved >%f m from last known position", log: self.log, type: .info, breadcrumbRadius)
            onBreadcrumbCrossed?(circularRegion.center)
            return
        }

        os_log("📍 [NativeGeofence] EXIT geofence: %{public}@", log: self.log, type: .info, circularRegion.identifier)
        
        processEvent(geofenceId: circularRegion.identifier, type: "EXIT", coordinate: circularRegion.center)
        onGeofenceRegionCrossed?("region_exit")
        
        // Clear persisted enter/dwell timestamp keys (Fix 1)
        if let defaults = sharedDefaults {
            defaults.removeObject(forKey: "enterTimestamp_\(circularRegion.identifier)")
            defaults.removeObject(forKey: "dwellFired_\(circularRegion.identifier)")
            defaults.synchronize()
        }
    }
    
    private func processEvent(geofenceId: String, type: String, coordinate: CLLocationCoordinate2D) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let event = GeofenceEvent(
            type: type,
            geofenceId: geofenceId,
            timestamp: timestamp,
            lat: coordinate.latitude,
            lng: coordinate.longitude
        )
        
        if let defaults = sharedDefaults {
            defaults.set("\(type)_\(geofenceId)_\(timestamp)", forKey: "com.truenyx.naviq.last_\(type.lowercased())_event")
            defaults.synchronize()
        }
        
        // Enqueue event natively
        NativeBackgroundSyncManager.shared.enqueue(event)
        
        // Trigger network sync only if config allows (Fix 2)
        let config = getApiConfig()
        if config.isSyncEnabled {
            NativeBackgroundSyncManager.shared.triggerSync()
        } else {
            os_log("⚠️ [NativeGeofence] Sync skipped: Backend endpoint currently unreachable", log: self.log, type: .info)
        }
        
        // Forward to Flutter via MethodChannel
        forwardToMethodChannel(event)
    }
    
    // MARK: - Non-Timer Dwell Detection (Fix 1)
    func checkDwellStatus(currentLocation: CLLocation?) {
        guard let location = currentLocation else { return }
        guard let defaults = sharedDefaults else { return }
        let currentGeofences = getGeofences()
        let now = Date().timeIntervalSince1970
        
        for fence in currentGeofences {
            let enterKey = "enterTimestamp_\(fence.id)"
            let firedKey = "dwellFired_\(fence.id)"
            
            let enterTime = defaults.double(forKey: enterKey)
            guard enterTime > 0 else { continue }
            
            let dwellFired = defaults.bool(forKey: firedKey)
            guard !dwellFired else { continue }
            
            let fenceLoc = CLLocation(latitude: fence.lat, longitude: fence.lng)
            let distance = location.distance(from: fenceLoc)
            
            if distance <= fence.radius {
                let duration = now - enterTime
                if duration >= 300 { // 5 minutes = 300 seconds
                    defaults.set(true, forKey: firedKey)
                    defaults.synchronize()
                    
                    processEvent(geofenceId: fence.id, type: "DWELL", coordinate: fenceLoc.coordinate)
                    os_log("📍 [NativeGeofence] DWELL event fired for geofence: %{public}@", log: self.log, type: .info, fence.id)
                }
            } else {
                // If they drifted outside radius, reset dwell status
                defaults.removeObject(forKey: enterKey)
                defaults.removeObject(forKey: firedKey)
                defaults.synchronize()
            }
        }
    }
    
    // MARK: - Method Channel Forwarding
    private func forwardToMethodChannel(_ event: GeofenceEvent) {
        guard let channel = methodChannel else { return }
        
        let arguments: [String: Any] = [
            "type": event.type,
            "geofenceId": event.geofenceId,
            "timestamp": event.timestamp,
            "lat": event.lat,
            "lng": event.lng
        ]
        
        DispatchQueue.main.async {
            channel.invokeMethod("onGeofenceEvent", arguments: arguments)
        }
    }
    
    private func notifyFlutterRegistered(geofenceId: String) {
        guard let channel = methodChannel else { return }
        DispatchQueue.main.async {
            channel.invokeMethod("onRegionRegistered", arguments: geofenceId)
        }
    }
    
    private func notifyFlutterUnregistered(geofenceId: String) {
        guard let channel = methodChannel else { return }
        DispatchQueue.main.async {
            channel.invokeMethod("onRegionRemoved", arguments: geofenceId)
        }
    }
    
    // MARK: - Health Check & Endpoint Availability (Fix 2)
    func runApiDiagnostics() {
        verifyEndpointReachability { [weak self] getOk, postOk in
            guard let self = self else { return }
            var config = self.getApiConfig()
            config.isGetReachable = getOk
            config.isPostReachable = postOk
            config.isSyncEnabled = getOk && postOk
            self.persistApiConfig(config)
            
            if config.isSyncEnabled {
                os_log("✅ [GeofenceHealth] Diagnostics passed: Sync enabled", log: self.log, type: .info)
                // Drain queue if now online
                NativeBackgroundSyncManager.shared.triggerSync()
            } else {
                os_log("⚠️ [GeofenceHealth] Diagnostics failed: GET=%@, POST=%@. Local monitoring continued.", log: self.log, type: .error, String(getOk), String(postOk))
            }
        }
    }
    
    private func verifyEndpointReachability(completion: @escaping (Bool, Bool) -> Void) {
        guard let defaults = sharedDefaults else {
            completion(false, false)
            return
        }
        let apiBase = defaults.string(forKey: "com.truenyx.naviq.api_base_url") ?? "https://naviq-server.codescap.com/api/v1/"
        let token = defaults.string(forKey: "com.truenyx.naviq.auth_token") ?? ""
        let childId = defaults.string(forKey: "com.truenyx.naviq.child_id") ?? ""
        
        guard !token.isEmpty && !childId.isEmpty else {
            completion(false, false)
            return
        }
        
        let getURL = URL(string: "\(apiBase)child/geofences?childId=\(childId)")!
        let postURL = URL(string: "\(apiBase)child/geofence-event")!
        
        var getRequest = URLRequest(url: getURL)
        getRequest.httpMethod = "GET"
        getRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        getRequest.timeoutInterval = 8.0
        
        var postRequest = URLRequest(url: postURL)
        postRequest.httpMethod = "POST"
        postRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let testPayload: [String: Any] = ["childId": childId, "events": []]
        postRequest.httpBody = try? JSONSerialization.data(withJSONObject: testPayload)
        postRequest.timeoutInterval = 8.0
        
        let group = DispatchGroup()
        var getOk = false
        var postOk = false
        
        group.enter()
        URLSession.shared.dataTask(with: getRequest) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                getOk = (httpResponse.statusCode == 200)
            }
            group.leave()
        }.resume()
        
        group.enter()
        URLSession.shared.dataTask(with: postRequest) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                postOk = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 500)
            }
            group.leave()
        }.resume()
        
        group.notify(queue: .main) {
            completion(getOk, postOk)
        }
    }
    
    private func checkForPeriodicSync() {
        guard let defaults = sharedDefaults else { return }
        let now = Date().timeIntervalSince1970
        let lastSync = defaults.double(forKey: kLastSyncTimeKey)
        
        if now - lastSync > 86400 {
            defaults.set(now, forKey: kLastSyncTimeKey)
            defaults.synchronize()
            fetchGeofencesFromBackend()
        }
    }
    
    func fetchGeofencesFromBackend() {
        guard let defaults = sharedDefaults,
              let token = defaults.string(forKey: "com.truenyx.naviq.auth_token"), !token.isEmpty,
              let childId = defaults.string(forKey: "com.truenyx.naviq.child_id"), !childId.isEmpty else {
            return
        }
        
        let apiBase = defaults.string(forKey: "com.truenyx.naviq.api_base_url") ?? "https://naviq-server.codescap.com/api/v1/"
        let urlString = "\(apiBase)child/geofences?childId=\(childId)"
        
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                let decoder = JSONDecoder()
                let geofences = try decoder.decode([NativeGeofence].self, from: data)
                DispatchQueue.main.async {
                    self.syncRegions(with: geofences)
                }
            } catch {
                os_log("❌ Failed to decode fetched geofences: %{public}@", log: self.log, type: .error, error.localizedDescription)
            }
        }.resume()
    }
    
    // MARK: - Native Diagnostics API
    func getDiagnostics() -> [String: Any] {
        guard let manager = locationManager else { return [:] }
        let persisted = getGeofences()
        let audit = RegionHealthMonitor.shared.auditRegions(manager: manager, persisted: persisted)
        let defaults = sharedDefaults
        
        let lastSync = defaults?.double(forKey: kLastSyncTimeKey) ?? 0.0
        let lastEnter = defaults?.string(forKey: "com.truenyx.naviq.last_enter_event") ?? "None"
        let lastExit = defaults?.string(forKey: "com.truenyx.naviq.last_exit_event") ?? "None"
        let lastDwell = defaults?.string(forKey: "com.truenyx.naviq.last_dwell_event") ?? "None"
        
        return [
            "monitoredRegionCount": manager.monitoredRegions.count,
            "persistedRegionCount": persisted.count,
            "lastGeofenceSyncTime": lastSync,
            "lastEnterEventId": lastEnter,
            "lastExitEventId": lastExit,
            "lastDwellEventId": lastDwell,
            "healthIssues": audit.issues,
            "isHealthy": audit.isHealthy
        ]
    }
}

// MARK: - Region Health Audit (Fix 3)
class RegionHealthMonitor {
    static let shared = RegionHealthMonitor()
    private let log = OSLog(subsystem: "com.truenyx.naviq", category: "RegionHealthMonitor")
    
    func auditRegions(manager: CLLocationManager, persisted: [NativeGeofence]) -> (isHealthy: Bool, issues: [String]) {
        // The breadcrumb circle (see IOSNativeGeofenceManager.armBreadcrumb)
        // is deliberately not part of `persisted` — it's not a parent
        // geofence — so it's excluded from this audit entirely rather than
        // being flagged as a mismatch on every foreground.
        let monitored = manager.monitoredRegions.filter {
            !IOSNativeGeofenceManager.shared.isBreadcrumb($0.identifier)
        }
        var issues: [String] = []

        if monitored.count != persisted.count {
            issues.append("Region count mismatch: Monitored \(monitored.count) vs Persisted \(persisted.count)")
        }

        for fence in persisted {
            let found = monitored.contains { $0.identifier == fence.id }
            if !found {
                issues.append("Missing monitored region: \(fence.id)")
            }
        }

        var idsSeen = Set<String>()
        for region in monitored {
            if idsSeen.contains(region.identifier) {
                issues.append("Duplicate monitored region: \(region.identifier)")
            }
            idsSeen.insert(region.identifier)

            let foundInPersisted = persisted.contains { $0.id == region.identifier }
            if !foundInPersisted {
                issues.append("Invalid region monitored: \(region.identifier)")
            }
        }
        
        let isHealthy = issues.isEmpty
        return (isHealthy, issues)
    }
}
