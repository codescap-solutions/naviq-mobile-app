package com.truenyx.naviqandroid

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import id.flutter.flutter_background_service.BackgroundService

/**
 * Brings the high-accuracy tracking service (flutter_background_service's
 * BackgroundService, which runs the Dart location stream) back when Android
 * allows it, and says honestly whether it is running.
 *
 * What Android permits (see developer.android.com "Restrictions on starting a
 * foreground service from the background"): after BOOT_COMPLETED /
 * MY_PACKAGE_REPLACED, on a geofencing transition, on a high-priority FCM
 * message, or when the app is exempt from battery optimization. A location-type
 * service additionally only reads location in the background when the app holds
 * ACCESS_BACKGROUND_LOCATION. Everything else (the WorkManager watchdog on a
 * non-exempt device, force-stop, an OEM kill with auto-start off) can fail —
 * a failure is recorded, never retried in a loop, and never hides the fact that
 * only the low-accuracy fallback is running.
 */
object TrackingRecovery {
    private const val TAG = "TrackingRecovery"
    private const val PREFS = "naviq_tracking_recovery"
    private const val KEY_LAST_ATTEMPT_AT = "last_attempt_at"
    private const val KEY_LAST_FAILED = "last_attempt_failed"
    private const val KEY_LAST_REASON = "last_reason"
    private const val KEY_LAST_RESULT = "last_result"

    /** Written by the Dart tracking isolate (TrackingRecoveryPolicy.aliveMarkerKey). */
    private const val FLUTTER_PREFS = NativeGeofenceManager.PREFS_NAME
    private const val KEY_ALIVE_AT = "flutter.bg_alive_at"

    /** The isolate refreshes its marker every 45 s; allow generous slack. */
    const val ALIVE_MAX_AGE_MS = 3 * 60 * 1000L
    const val MIN_GAP_MS = 60 * 1000L
    const val MIN_GAP_AFTER_FAILED_WATCHDOG_MS = 10 * 60 * 1000L

    enum class Reason { BOOT, PACKAGE_REPLACED, GEOFENCE, WATCHDOG }

    enum class Decision {
        START,
        SKIP_NOT_CHILD,
        SKIP_NO_LOCATION_PERMISSION,
        SKIP_NO_BACKGROUND_LOCATION,
        SKIP_ALREADY_RUNNING,
        SKIP_RECENT_ATTEMPT,
    }

    data class Inputs(
        val sdkInt: Int,
        val hasChildId: Boolean,
        val fineLocationGranted: Boolean,
        val backgroundLocationGranted: Boolean,
        val serviceRunning: Boolean,
        val msSinceLastAttempt: Long?,
        val lastAttemptFailed: Boolean,
        val reason: Reason,
    )

    /** Pure decision — no Android calls, unit-tested. */
    fun decide(i: Inputs): Decision {
        if (!i.hasChildId) return Decision.SKIP_NOT_CHILD
        if (!i.fineLocationGranted) return Decision.SKIP_NO_LOCATION_PERMISSION
        // Background location is a separate grant from Android 10 (API 29).
        if (i.sdkInt >= Build.VERSION_CODES.Q && !i.backgroundLocationGranted) {
            return Decision.SKIP_NO_BACKGROUND_LOCATION
        }
        if (i.serviceRunning) return Decision.SKIP_ALREADY_RUNNING
        val gap = if (i.lastAttemptFailed && i.reason == Reason.WATCHDOG) {
            MIN_GAP_AFTER_FAILED_WATCHDOG_MS
        } else {
            MIN_GAP_MS
        }
        if (i.msSinceLastAttempt != null && i.msSinceLastAttempt in 0 until gap) {
            return Decision.SKIP_RECENT_ATTEMPT
        }
        return Decision.START
    }

    /** True when `ageMs` is a fresh heartbeat of the Dart isolate. */
    fun isAliveMarkerFresh(ageMs: Long?): Boolean = ageMs != null && ageMs in 0..ALIVE_MAX_AGE_MS

    // ── Android-facing ───────────────────────────────────────────────────────

    @Suppress("DEPRECATION") // getRunningServices only returns this app's own services on API 26+
    fun isServiceRunning(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.getRunningServices(Int.MAX_VALUE).any {
                it.service.className == BackgroundService::class.java.name
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * The high-accuracy path is active only if the service exists AND its Dart
     * isolate has recently said so. A fallback ping, an FCM message or the bare
     * existence of the service does not count.
     */
    fun isHighAccuracyActive(context: Context): Boolean {
        if (!isServiceRunning(context)) return false
        val at = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).getLong(KEY_ALIVE_AT, 0L)
        val age = if (at > 0) System.currentTimeMillis() - at else null
        return isAliveMarkerFresh(age)
    }

    /**
     * Re-arm the native low-accuracy fallback (location ping, watchdog,
     * geofences). Neither a reboot nor an app update keeps these registrations,
     * so this runs from the boot/replace receiver. Only for a logged-in child
     * with location permission; geofences are re-registered WITHOUT initial
     * triggers (see NativeGeofenceManager) so this cannot fabricate ENTRY hints.
     */
    fun rearmNativeFallback(context: Context) {
        val app = context.applicationContext
        if (NativeApiClient.getChildId(app).isNullOrEmpty()) return
        if (!hasFineLocation(app)) return
        NativeLocationPingManager.start(app)
        LocationWatchdogWorker.schedule(app)
        val fences = NativeGeofenceManager.getPersistedGeofences(app)
        if (fences.isNotEmpty()) NativeGeofenceManager.syncGeofences(app, fences)
    }

    /**
     * Everything [run] needs from the outside world, so the orchestration
     * (guards, duplicate-start protection, failure bookkeeping) is unit-tested on
     * the JVM with a fake instead of a device.
     */
    interface Env {
        val sdkInt: Int
        fun hasChildId(): Boolean
        fun fineLocationGranted(): Boolean
        fun backgroundLocationGranted(): Boolean
        fun serviceRunning(): Boolean
        fun nowMs(): Long
        fun lastAttemptAtMs(): Long
        fun lastAttemptFailed(): Boolean

        /** Ask Android to start the service. May throw (e.g. ForegroundServiceStartNotAllowedException). */
        fun startService()
        fun recordAttempt(atMs: Long, failed: Boolean, reason: Reason, result: String)
        fun log(message: String)
    }

    /**
     * Decide and, if allowed, request the start. Never throws; a refused start is
     * recorded (and backed off), never retried in a loop, and never touches the
     * native fallback. Returns START when a start was REQUESTED — the caller must
     * not read that as "tracking is healthy" (see [isHighAccuracyActive]).
     */
    fun run(env: Env, reason: Reason): Decision {
        val lastAt = env.lastAttemptAtMs()
        val decision = decide(
            Inputs(
                sdkInt = env.sdkInt,
                hasChildId = env.hasChildId(),
                fineLocationGranted = env.fineLocationGranted(),
                backgroundLocationGranted = env.backgroundLocationGranted(),
                serviceRunning = env.serviceRunning(),
                msSinceLastAttempt = if (lastAt > 0) env.nowMs() - lastAt else null,
                lastAttemptFailed = env.lastAttemptFailed(),
                reason = reason,
            )
        )
        if (decision != Decision.START) {
            if (decision != Decision.SKIP_ALREADY_RUNNING && decision != Decision.SKIP_NOT_CHILD) {
                env.log("skip reason=$reason decision=$decision")
            }
            return decision
        }

        var failed = false
        var result = "requested"
        try {
            env.startService()
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException (API 31+), SecurityException, ...
            failed = true
            result = e.javaClass.simpleName
        }
        env.recordAttempt(env.nowMs(), failed, reason, result)
        env.log("start reason=$reason result=$result")
        return Decision.START
    }

    /** The real device environment. */
    private class AndroidEnv(private val app: Context) : Env {
        private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        override val sdkInt: Int get() = Build.VERSION.SDK_INT
        override fun hasChildId() = !NativeApiClient.getChildId(app).isNullOrEmpty()
        override fun fineLocationGranted() = hasFineLocation(app)
        override fun backgroundLocationGranted() = hasBackgroundLocation(app)
        override fun serviceRunning() = isServiceRunning(app)
        override fun nowMs() = System.currentTimeMillis()
        override fun lastAttemptAtMs() = prefs.getLong(KEY_LAST_ATTEMPT_AT, 0L)
        override fun lastAttemptFailed() = prefs.getBoolean(KEY_LAST_FAILED, false)
        override fun startService() {
            ContextCompat.startForegroundService(app, Intent(app, BackgroundService::class.java))
        }
        override fun recordAttempt(atMs: Long, failed: Boolean, reason: Reason, result: String) {
            prefs.edit()
                .putLong(KEY_LAST_ATTEMPT_AT, atMs)
                .putBoolean(KEY_LAST_FAILED, failed)
                .putString(KEY_LAST_REASON, reason.name)
                .putString(KEY_LAST_RESULT, result)
                .apply()
        }
        override fun log(message: String) {
            if (message.startsWith("start") && message.contains("result=") && !message.endsWith("result=requested")) {
                Log.w(TAG, "foreground service start refused: $message")
            }
            NativeFileLogger.log(app, "RECOVERY", message)
        }
    }

    fun ensureRunning(context: Context, reason: Reason): Decision =
        run(AndroidEnv(context.applicationContext), reason)

    private fun hasFineLocation(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasBackgroundLocation(context: Context) =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
}
