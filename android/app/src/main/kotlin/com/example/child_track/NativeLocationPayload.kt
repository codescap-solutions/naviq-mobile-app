package com.truenyx.naviqandroid

import android.content.Context
import androidx.core.content.pm.PackageInfoCompat
import org.json.JSONObject

/**
 * Payload helpers shared by the native receivers that POST /child/location.
 *
 * Speed: a fix that carries no speed reading (network fixes, many first fixes)
 * is UNKNOWN, never "0 m/s". The backend's drive-by arrival guard only trusts a
 * KNOWN slow speed as proof the child has stopped, so an unknown speed is left
 * out of the payload and flagged with `speed_known=false`.
 */
object NativeLocationPayload {
    /** The speed in m/s when the fix really carries one, else null. */
    fun knownSpeedMps(hasSpeed: Boolean, speed: Float): Double? =
        if (hasSpeed && speed.isFinite() && speed >= 0f) speed.toDouble() else null

    fun putSpeed(payload: JSONObject, hasSpeed: Boolean, speed: Float, legacyAlias: Boolean = true) {
        val v = knownSpeedMps(hasSpeed, speed)
        if (v == null) {
            payload.put("speed_known", false)
        } else {
            payload.put("speed_mps", v)
            if (legacyAlias) payload.put("speed", v)
            payload.put("speed_known", true)
        }
    }

    /**
     * Engineering diagnostics (never shown to a parent, never used for a
     * decision): platform, app build, which tracking layer produced the fix and
     * whether the high-accuracy service was alive at that moment.
     */
    fun putDiagnostics(context: Context, payload: JSONObject, fixSource: String, profile: String?) {
        payload.put("platform", "android")
        payload.put("fix_source", fixSource)
        if (profile != null) payload.put("tracking_profile", profile)
        payload.put("fgs_running", TrackingRecovery.isHighAccuracyActive(context))
        try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            info.versionName?.let { payload.put("app_version", it) }
            payload.put("app_build", PackageInfoCompat.getLongVersionCode(info).toString())
        } catch (_: Exception) {
            // optional diagnostics — never block a location post
        }
    }
}
