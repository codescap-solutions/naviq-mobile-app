package com.truenyx.naviqandroid

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * AccessibilityService that monitors foreground app changes and blocks
 * apps whose package names are in the [lockedPackages] set.
 *
 * When a locked app is detected:
 * 1. Immediately performs GLOBAL_ACTION_BACK to dismiss it.
 * 2. Launches MainActivity with an "app_blocked" extra so the Flutter
 *    side can display the "App Blocked" screen.
 *
 * The [lockedPackages] set is updated from Flutter via DeviceInfoPlugin's
 * "updateLockList" MethodChannel call.
 */
class AppLockService : AccessibilityService() {

    companion object {
        private const val TAG = "AppLockService"
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        // Read the CSV string we now save from Flutter
        private const val FLUTTER_PREFS_CSV_KEY = "flutter.locked_packages_csv"
        private const val FLUTTER_PREFS_WEB_FILTER_KEY = "flutter.block_18plus"
        private const val FLUTTER_PREFS_RESTRICT_DELETE_KEY = "flutter.restrict_deletion"
        private const val FLUTTER_PREFS_ALLOW_DELETE_KEY = "flutter.is_allow_delete"

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "org.mozilla.firefox",
            "com.sec.android.app.sbrowser", // Samsung Browser
            "com.opera.browser",
            "com.opera.mini.native",
            "com.microsoft.emmx", // Edge
            "com.duckduckgo.mobile.android",
            "com.brave.browser",
            "com.vivaldi.browser",
            "org.mozilla.focus",
            "org.mozilla.fenix",
            "org.mozilla.firefox_beta",
            "com.kiwibrowser.browser",
            "com.opera.gx",
            "com.UCMobile.intl",
            "com.mi.globalbrowser", // Xiaomi
            "com.heytap.browser", // Oppo / Realme
            "com.huawei.browser",
            "com.android.browser",
            "com.chrome.beta",
            "com.chrome.dev"
        )

        /**
         * Thread-safe set of package names currently blocked.
         * Updated from [DeviceInfoPlugin] when Flutter calls "updateLockList",
         * AND periodically refreshed from SharedPreferences.
         */
        @Volatile
        var lockedPackages: Set<String> = emptySet()
            private set

        @Volatile
        var webFilteringEnabled: Boolean = false
            private set

        @Volatile
        var deletionRestricted: Boolean = false
            private set

        /**
         * Replace the entire locked-packages set (called from DeviceInfoPlugin).
         * Also persists to SharedPreferences for cross-process access.
         */
        fun updateLockedPackages(packages: Set<String>, context: android.content.Context? = null) {
            lockedPackages = packages
            Log.d(TAG, ">>> Locked packages updated (MethodChannel): $packages")
            
            // Write as a comma-separated string to match Flutter's CSV writing logic
            context?.let {
                try {
                    val prefs = it.getSharedPreferences(FLUTTER_PREFS_NAME, android.content.Context.MODE_PRIVATE)
                    val csv = packages.joinToString(",")
                    prefs.edit().putString(FLUTTER_PREFS_CSV_KEY, csv).apply()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to write locked packages to prefs: ${e.message}")
                }
            }
        }

        /**
         * Check whether this AccessibilityService is currently enabled
         * in the device's accessibility settings.
         */
        fun isServiceEnabled(context: Context): Boolean {
            val expectedComponent = ComponentName(context, AppLockService::class.java)
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false

            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServices)
            while (colonSplitter.hasNext()) {
                val componentStr = colonSplitter.next()
                val enabledComponent = ComponentName.unflattenFromString(componentStr)
                if (enabledComponent != null && enabledComponent == expectedComponent) {
                    return true
                }
            }
            return false
        }
    }

    // Track the last time we refreshed from SharedPreferences
    private var lastPrefsRefreshTime: Long = 0L
    private val PREFS_REFRESH_INTERVAL_MS = 1000L  // refresh every 1s for near-instant lock enforcement

    // Track the last blocked package to avoid spamming intents.
    private var lastBlockedPackage: String? = null
    private var lastBlockedTime: Long = 0L
    // 1.5 s is enough to suppress re-triggers from the window events
    // that our own activity launch generates.
    private val BLOCK_DEBOUNCE_MS = 1500L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, ">>> AppLockService connected (v7 — SharedPrefs sync)")

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or 
                         AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100L
            flags = AccessibilityServiceInfo.DEFAULT or 
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        serviceInfo = info

        // Load locked packages from SharedPreferences on startup
        refreshLockedPackagesFromPrefs()
    }

    /**
     * Re-reads the locked packages list from SharedPreferences.
     * Flutter's background FCM handler writes here when it can't use MethodChannel.
     */
    private fun refreshLockedPackagesFromPrefs() {
        try {
            val prefs = applicationContext.getSharedPreferences(
                FLUTTER_PREFS_NAME, android.content.Context.MODE_PRIVATE
            )
            val csv = prefs.getString(FLUTTER_PREFS_CSV_KEY, null)
            if (csv != null) {
                // If it's empty, split(",") returns [""] so we filter out blanks
                val savedPackages = if (csv.isBlank()) emptySet() else csv.split(",").toSet()
                if (savedPackages != lockedPackages) {
                    lockedPackages = savedPackages
                    Log.d(TAG, ">>> Refreshed locked packages from SharedPrefs CSV: $savedPackages")
                }
            }
            
            val webEnabled = prefs.getBoolean(FLUTTER_PREFS_WEB_FILTER_KEY, false)
            if (webEnabled != webFilteringEnabled) {
                webFilteringEnabled = webEnabled
                Log.d(TAG, ">>> Web filtering status updated: $webEnabled")
            }

            val restrictDeletePref = prefs.getBoolean(FLUTTER_PREFS_RESTRICT_DELETE_KEY, false)
            val allowDeletePref = prefs.getBoolean(FLUTTER_PREFS_ALLOW_DELETE_KEY, true)
            val restricted = restrictDeletePref || !allowDeletePref
            if (restricted != deletionRestricted) {
                deletionRestricted = restricted
                Log.d(TAG, ">>> Deletion restricted status updated: $restricted")
            }

            lastPrefsRefreshTime = System.currentTimeMillis()
        } catch (e: Exception) {
            Log.e(TAG, ">>> Failed to read locked packages from prefs: ${e.message}")
        }
    }

    // shortcut: launcher/keyboard sets are cached 60s, so a just-installed keyboard
    // stays blockable for up to a minute; fine unless it becomes a bypass.
    private var exemptPackages: Set<String> = emptySet()
    private var exemptPackagesAt: Long = 0L

    private fun isLauncherOrKeyboard(packageName: String): Boolean {
        val now = System.currentTimeMillis()
        if (now - exemptPackagesAt > 60_000L) {
            try {
                val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                val launchers = packageManager.queryIntentActivities(home, 0)
                    .map { it.activityInfo.packageName }
                val imm = getSystemService(Context.INPUT_METHOD_SERVICE)
                    as android.view.inputmethod.InputMethodManager
                val keyboards = imm.enabledInputMethodList.map { it.packageName }
                exemptPackages = (launchers + keyboards).toSet()
                exemptPackagesAt = now
            } catch (e: Exception) {
                Log.e(TAG, ">>> Failed to resolve launcher/keyboard packages: ${e.message}")
            }
        }
        return packageName in exemptPackages
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        val eventType = event.eventType
        val packageName = event.packageName?.toString() ?: return

        // Periodically refresh settings from SharedPreferences.
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastPrefsRefreshTime > PREFS_REFRESH_INTERVAL_MS) {
            refreshLockedPackagesFromPrefs()
        }

        // Intercept uninstallation attempts if deletion restriction is active
        checkForUninstall(packageName, event)

        // Web Filtering Debug
        if (BROWSER_PACKAGES.contains(packageName)) {
            Log.d(TAG, ">>> BROWSER DETECTED: $packageName (FilteringEnabled=$webFilteringEnabled)")
        }

        // Log window changes
        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            Log.d(TAG, ">>> Window changed to: $packageName (className=${event.className})")
        }

        // Skip system UI
        if (packageName == "com.android.systemui") return

        // When NaviQ comes to foreground, reset debounce
        if (packageName == applicationContext.packageName) {
            Log.d(TAG, ">>> NaviQ is foreground — resetting debounce (was=$lastBlockedPackage)")
            lastBlockedPackage = null
            lastBlockedTime = 0L
            return
        }

        if (packageName !in lockedPackages) {
            // If web filtering is enabled and it's a browser, check the URL
            if (webFilteringEnabled && BROWSER_PACKAGES.contains(packageName)) {
                checkWebFiltering(packageName, event)
            }
            return
        }

        // "Block All" can sweep the launcher / keyboard into the locked list; blocking
        // them pops the block screen while the child just types in launcher search.
        if (isLauncherOrKeyboard(packageName)) {
            Log.d(TAG, ">>> Skipping block for launcher/keyboard: $packageName")
            return
        }

        val now = System.currentTimeMillis()

        // Debounce check
        if (packageName == lastBlockedPackage &&
            (now - lastBlockedTime) < BLOCK_DEBOUNCE_MS
        ) {
            val elapsed = now - lastBlockedTime
            Log.d(TAG, ">>> DEBOUNCED: $packageName (${elapsed}ms < ${BLOCK_DEBOUNCE_MS}ms)")
            return
        }

        lastBlockedPackage = packageName
        lastBlockedTime = now

        Log.d(TAG, ">>> BLOCKING: $packageName — launching NaviQ intent")

        // Launch our app immediately so it covers the blocked app
        try {
            val intent = Intent(applicationContext, MainActivity::class.java).apply {
                action = "com.truenyx.naviqandroid.APP_BLOCKED"
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                putExtra("app_blocked", true)
                putExtra("blocked_package", packageName)
            }
            applicationContext.startActivity(intent)
            Log.d(TAG, ">>> Intent sent successfully for: $packageName")
        } catch (e: Exception) {
            Log.e(TAG, ">>> FAILED to launch intent: ${e.message}", e)
        }
    }

    /**
     * Scans the browser's node hierarchy to find and check the URL.
     */
    private fun checkWebFiltering(packageName: String, event: AccessibilityEvent) {
        // Try getting the node from the event source first (more efficient)
        var rootNode = event.source
        
        if (rootNode == null) {
            // Fallback to root in active window
            rootNode = rootInActiveWindow
        }

        if (rootNode == null) {
            Log.w(TAG, ">>> WebFilter: BOTH event.source and rootInActiveWindow are NULL for $packageName")
            return
        }
        
        Log.d(TAG, ">>> WebFilter: Scanning nodes for $packageName (Event: ${AccessibilityEvent.eventTypeToString(event.eventType)})...")
        val url = findUrlInNodes(rootNode)
        
        // Don't recycle if it's the event source, only if we got it from rootInActiveWindow
        // Actually, the documentation says we SHOULD recycle if we are done.
        rootNode.recycle()

        if (url != null) {
            Log.d(TAG, ">>> WebFilter: URL FOUND: $url")
            if (AdultSiteFilter.isBlocked(url)) {
                Log.d(TAG, ">>> WebFilter: BLOCKED adult site: $url")
                triggerBlock(packageName, url)
            }
        } else {
            // Optional: Log once every few seconds to avoid flood
            // Log.v(TAG, ">>> WebFilter: No URL found in current view for $packageName")
        }
    }

    private fun findUrlInNodes(node: AccessibilityNodeInfo, depth: Int = 0): String? {
        val text = node.text?.toString()
        val className = node.className?.toString() ?: ""
        val resourceId = node.viewIdResourceName ?: ""
        
        // Debug log for every node (limited to avoid log flood, only if it looks interesting)
        if (text != null && text.length > 3) {
            // Log.v(TAG, "Node[d=$depth]: class=$className, id=$resourceId, text=$text")
        }

        // Patterns for address bars
        if (text != null && (text.contains(".") || text.contains("http") || text.contains("www"))) {
            // Many browsers use specific IDs for address bars
            // Chrome: com.android.chrome:id/url_bar
            // Firefox: org.mozilla.firefox:id/url_bar_title
            if (resourceId.contains("url") || resourceId.contains("address") || node.isEditable) {
                Log.i(TAG, ">>> WebFilter: Potential URL found in node: $text (ID: $resourceId)")
                return text
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findUrlInNodes(child, depth + 1)
            child.recycle()
            if (result != null) return result
        }
        return null
    }

    private fun triggerBlock(packageName: String, url: String) {
        val now = System.currentTimeMillis()
        if (packageName == lastBlockedPackage && (now - lastBlockedTime) < BLOCK_DEBOUNCE_MS) return
        
        lastBlockedPackage = packageName
        lastBlockedTime = now

        try {
            val intent = Intent(applicationContext, MainActivity::class.java).apply {
                action = "com.truenyx.naviqandroid.APP_BLOCKED"
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                putExtra("app_blocked", true)
                putExtra("blocked_package", packageName)
                putExtra("blocked_url", url)
            }
            applicationContext.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, ">>> FAILED to launch web block intent: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "AppLockService interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "AppLockService destroyed")
    }

    private fun checkForUninstall(packageName: String, event: AccessibilityEvent) {
        if (!deletionRestricted) return

        val isInstaller = packageName == "com.google.android.packageinstaller" || 
                          packageName == "com.android.packageinstaller"
        val isSettings = packageName == "com.android.settings"

        if (!isInstaller && !isSettings) return

        var rootNode = event.source ?: rootInActiveWindow ?: return

        try {
            val appPackage = applicationContext.packageName
            val appLabel = "NaviQ"

            val hasAppDetails = containsText(rootNode, appPackage) || containsText(rootNode, appLabel)
            
            if (hasAppDetails) {
                var shouldBlock = false
                if (isInstaller) {
                    shouldBlock = true
                } else if (isSettings) {
                    val className = event.className?.toString() ?: ""
                    val isAppDetailsScreen = className.contains("InstalledAppDetails") ||
                                             containsText(rootNode, "Uninstall") ||
                                             containsText(rootNode, "Force stop")
                    if (isAppDetailsScreen) {
                        shouldBlock = true
                    }
                }

                if (shouldBlock) {
                    Log.w(TAG, ">>> Deletion restriction triggered! Blocking package: $packageName")
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    triggerHomeRedirect()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in checkForUninstall: ${e.message}")
        } finally {
            try {
                rootNode.recycle()
            } catch (e: Exception) {
                // ignore
            }
        }
    }

    private fun containsText(node: AccessibilityNodeInfo, query: String): Boolean {
        val text = node.text?.toString()
        if (text != null && text.contains(query, ignoreCase = true)) {
            return true
        }
        val contentDesc = node.contentDescription?.toString()
        if (contentDesc != null && contentDesc.contains(query, ignoreCase = true)) {
            return true
        }
        val resourceId = node.viewIdResourceName
        if (resourceId != null && resourceId.contains(query, ignoreCase = true)) {
            return true
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = containsText(child, query)
            try {
                child.recycle()
            } catch (e: Exception) {
                // ignore
            }
            if (found) return true
        }
        return false
    }

    private fun triggerHomeRedirect() {
        try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            Log.d(TAG, "Home redirect intent sent successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch home redirect: ${e.message}")
        }
    }
}
