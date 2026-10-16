package com.truenyx.naviqandroid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot / app-update handler. Neither a reboot nor an app update keeps the
 * native fallback registrations (location ping, geofences), and the
 * high-accuracy service is stopped by an update — both are documented
 * moments at which Android lets the app start a foreground service again.
 *
 * (flutter_background_service also ships its own receiver for these actions;
 * both may fire. TrackingRecovery guards on "already running", and the plugin
 * ignores a start while its engine is up, so a double start is harmless.)
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val reason = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, "android.intent.action.QUICKBOOT_POWERON" -> TrackingRecovery.Reason.BOOT
            Intent.ACTION_MY_PACKAGE_REPLACED -> TrackingRecovery.Reason.PACKAGE_REPLACED
            else -> return
        }
        Log.d(TAG, "onReceive: $reason")
        try {
            TrackingRecovery.rearmNativeFallback(context)
            TrackingRecovery.ensureRunning(context, reason)
        } catch (e: Exception) {
            // A receiver must never crash the process on boot.
            Log.w(TAG, "recovery after $reason failed: ${e.javaClass.simpleName}")
        }
    }
}
