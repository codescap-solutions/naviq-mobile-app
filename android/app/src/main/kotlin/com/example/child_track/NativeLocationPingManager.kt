package com.truenyx.naviqandroid

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Registers a periodic background location request via
 * FusedLocationProviderClient + PendingIntent — Android's analog to iOS's
 * continuous CLLocationManager updates (AppDelegate.swift startLocationServices).
 * Delivery goes through Play Services directly to a manifest-registered
 * BroadcastReceiver, independent of this app's process, so it continues after
 * a force-kill — subject to Android's own background-location frequency
 * throttle for apps without an active foreground component. The REQUESTED
 * interval below is not a guarantee; report the actual observed delivery
 * interval from real-device testing rather than assuming it's honored.
 *
 * This is a baseline "the map shouldn't go completely stale" signal — the
 * foreground service (LocationStateMachine) remains the primary, far more
 * frequent path whenever the app is actually running; this just fills the gap
 * when it isn't.
 */
object NativeLocationPingManager {
    private const val TAG = "NativeLocationPing"
    private const val REQUEST_CODE = 4472

    private const val INTERVAL_MS = 3 * 60 * 1000L // 3 minutes — requested, not guaranteed
    private const val MIN_UPDATE_INTERVAL_MS = 2 * 60 * 1000L // 2 minutes — fastest we'll accept

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, LocationPingBroadcastReceiver::class.java).apply {
            action = LocationPingBroadcastReceiver.ACTION_LOCATION_PING
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getBroadcast(context.applicationContext, REQUEST_CODE, intent, flags)
    }

    /** Idempotent — safe to call repeatedly (used by the WorkManager watchdog too). */
    fun start(context: Context) {
        val appContext = context.applicationContext
        val client = LocationServices.getFusedLocationProviderClient(appContext)

        val request = LocationRequest.Builder(INTERVAL_MS)
            .setMinUpdateIntervalMillis(MIN_UPDATE_INTERVAL_MS)
            .setPriority(Priority.PRIORITY_BALANCED_POWER_ACCURACY)
            .build()

        try {
            client.requestLocationUpdates(request, pendingIntent(appContext))
                .addOnSuccessListener { Log.i(TAG, "Native background location updates registered") }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to register background location updates: ${e.message}", e)
                }
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing location permission for background updates: ${e.message}")
        }
    }

    fun stop(context: Context) {
        val appContext = context.applicationContext
        val client = LocationServices.getFusedLocationProviderClient(appContext)
        client.removeLocationUpdates(pendingIntent(appContext))
        NearFenceBurst.cancel(appContext)
    }
}
