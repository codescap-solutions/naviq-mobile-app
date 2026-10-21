package com.truenyx.naviqandroid

import android.content.Context
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Watchdog only — NOT the primary delivery mechanism for either location pings
 * (NativeLocationPingManager) or geofence transitions (NativeGeofenceManager).
 * This periodically re-arms both registrations in case Play Services silently
 * dropped them, which is a known real-world occurrence after a Play Services
 * update or a device reboot — without this, a dropped geofence registration
 * would otherwise only get restored the next time the Dart isolate happens to
 * be alive and runs its own periodic refresh, defeating the point of native
 * geofencing surviving a prolonged force-kill.
 *
 * 15 minutes is WorkManager's hard floor for periodic work (PeriodicWorkRequest
 * .MIN_PERIODIC_INTERVAL_MILLIS) — it cannot be configured shorter.
 */
class LocationWatchdogWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val childId = NativeApiClient.getChildId(applicationContext)
        if (!childId.isNullOrEmpty()) {
            Log.i("LocationWatchdog", "Re-arming native background location updates")
            NativeFileLogger.log(applicationContext, "WATCHDOG", "re-arming location pings")
            NativeLocationPingManager.start(applicationContext)
            // Only a REQUEST: on a device that is not battery-optimization-exempt Android
            // may refuse a foreground-service start from WorkManager. A refusal is recorded
            // and backed off; the native fallback above keeps running either way.
            TrackingRecovery.ensureRunning(applicationContext, TrackingRecovery.Reason.WATCHDOG)

            val persistedFences = NativeGeofenceManager.getPersistedGeofences(applicationContext)
            if (persistedFences.isNotEmpty()) {
                Log.i("LocationWatchdog", "Re-arming ${persistedFences.size} native geofences")
                NativeFileLogger.log(applicationContext, "WATCHDOG", "re-arming ${persistedFences.size} geofences")
                NativeGeofenceManager.syncGeofences(applicationContext, persistedFences)
            }
        }
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "native_location_watchdog"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<LocationWatchdogWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
