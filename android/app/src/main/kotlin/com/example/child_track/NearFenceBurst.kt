package com.truenyx.naviqandroid

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * A bounded, self-expiring HIGH_ACCURACY location request used only while the
 * high-accuracy foreground service is not running and the child is near a saved
 * place (decided by [NearFencePolicy] from the fallback ping's fix).
 *
 * Bounded three ways: the request carries its own duration + max update count
 * (Play Services stops it by itself, even if this process is dead), a cooldown
 * prevents back-to-back bursts, and it is cancelled the moment the real
 * foreground service is alive or tracking is stopped. It never touches the
 * geofence registrations, so it cannot create ENTRY/EXIT hints.
 *
 * Limitation (needs real-device validation): without a foreground service,
 * Android throttles background location, so a burst may deliver fewer / older
 * fixes than requested. Fixes that are not fresh and precise are discarded by
 * [NearFencePolicy.isUsableBurstFix]; the burst can only help, never produce
 * false evidence.
 */
object NearFenceBurst {
    private const val TAG = "NearFenceBurst"
    const val ACTION_NEAR_FENCE_BURST = "com.truenyx.naviqandroid.NEAR_FENCE_BURST"
    private const val REQUEST_CODE = 4473
    private const val PREFS = "naviq_near_fence_burst"
    private const val KEY_ACTIVE_UNTIL = "active_until"
    private const val KEY_LAST_START = "last_start"

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, LocationPingBroadcastReceiver::class.java).apply {
            action = ACTION_NEAR_FENCE_BURST
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_MUTABLE
        return PendingIntent.getBroadcast(context.applicationContext, REQUEST_CODE, intent, flags)
    }

    /** What [decideAndStart] needs from the device — faked in JVM unit tests. */
    interface Env {
        fun fences(): List<NearFencePolicy.Fence>
        fun highAccuracyActive(): Boolean
        fun nowMs(): Long
        fun activeUntilMs(): Long
        fun lastStartMs(): Long

        /** Register the bounded request with Play Services. Returns false if it could not (e.g. no permission). */
        fun requestBurst(): Boolean
        fun recordStart(nowMs: Long)
        fun log(message: String)
    }

    /**
     * Start a burst iff [NearFencePolicy] says so, from a fallback ping's fix.
     * Returns true only when a request was actually registered.
     */
    fun decideAndStart(env: Env, lat: Double, lng: Double, accuracyM: Double?): Boolean {
        val fences = env.fences()
        if (fences.isEmpty()) return false
        val now = env.nowMs()
        val should = NearFencePolicy.shouldStartBurst(
            NearFencePolicy.BurstInputs(
                highAccuracyActive = env.highAccuracyActive(),
                nearBoundary = NearFencePolicy.isNearBoundary(lat, lng, accuracyM, fences),
                nowMs = now,
                activeUntilMs = env.activeUntilMs(),
                lastBurstStartMs = env.lastStartMs(),
            )
        )
        if (!should) return false
        if (!env.requestBurst()) return false
        env.recordStart(now)
        env.log("started duration=${NearFencePolicy.BURST_DURATION_MS / 1000}s")
        return true
    }

    private class AndroidEnv(private val app: Context) : Env {
        private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        override fun fences() = NativeGeofenceManager.getPersistedGeofences(app).mapNotNull {
            val lat = (it["lat"] as? Number)?.toDouble()
            val lng = (it["lng"] as? Number)?.toDouble()
            val radius = (it["radius"] as? Number)?.toDouble()
            if (lat == null || lng == null || radius == null) null else NearFencePolicy.Fence(lat, lng, radius)
        }
        override fun highAccuracyActive() = TrackingRecovery.isHighAccuracyActive(app)
        override fun nowMs() = System.currentTimeMillis()
        override fun activeUntilMs() = prefs.getLong(KEY_ACTIVE_UNTIL, 0L)
        override fun lastStartMs() = prefs.getLong(KEY_LAST_START, 0L)
        override fun requestBurst(): Boolean {
            val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, NearFencePolicy.BURST_INTERVAL_MS)
                .setMinUpdateIntervalMillis(NearFencePolicy.BURST_MIN_INTERVAL_MS)
                .setMaxUpdates(NearFencePolicy.BURST_MAX_UPDATES)
                .setDurationMillis(NearFencePolicy.BURST_DURATION_MS)
                .setMaxUpdateAgeMillis(0L) // never hand back a cached position as the first update
                .setWaitForAccurateLocation(false)
                .build()
            return try {
                LocationServices.getFusedLocationProviderClient(app)
                    .requestLocationUpdates(request, pendingIntent(app))
                    .addOnFailureListener { e -> Log.w(TAG, "burst registration failed: ${e.message}") }
                true
            } catch (e: SecurityException) {
                Log.w(TAG, "no location permission for burst")
                false
            }
        }
        override fun recordStart(nowMs: Long) {
            prefs.edit()
                .putLong(KEY_ACTIVE_UNTIL, nowMs + NearFencePolicy.BURST_DURATION_MS)
                .putLong(KEY_LAST_START, nowMs)
                .apply()
        }
        override fun log(message: String) = NativeFileLogger.log(app, "NEAR_FENCE_BURST", message)
    }

    /** Start a burst if the policy says so. Returns true if one was started. */
    fun maybeStart(context: Context, fix: Location): Boolean =
        decideAndStart(
            AndroidEnv(context.applicationContext),
            fix.latitude, fix.longitude,
            if (fix.hasAccuracy()) fix.accuracy.toDouble() else null,
        )

    /** Cancel an active burst (tracking stopped, or the real service is alive). */
    fun cancel(context: Context) {
        val app = context.applicationContext
        try {
            LocationServices.getFusedLocationProviderClient(app).removeLocationUpdates(pendingIntent(app))
        } catch (_: Exception) {
        }
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(KEY_ACTIVE_UNTIL, 0L).apply()
    }

    /** Drop an active burst once the real foreground service is alive (no duplicate streams). */
    fun cancelIfSuperseded(context: Context) {
        val app = context.applicationContext
        val until = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_ACTIVE_UNTIL, 0L)
        if (NearFencePolicy.shouldCancelSuperseded(until, System.currentTimeMillis(), TrackingRecovery.isHighAccuracyActive(app))) cancel(app)
    }

    /** Age of a fix on the monotonic clock, or null if the platform gave none. */
    fun fixAgeMs(fix: Location): Long? =
        if (fix.elapsedRealtimeNanos > 0) (SystemClock.elapsedRealtimeNanos() - fix.elapsedRealtimeNanos) / 1_000_000L else null
}
