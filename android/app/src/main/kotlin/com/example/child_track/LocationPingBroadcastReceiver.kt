package com.truenyx.naviqandroid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.util.Log
import com.google.android.gms.location.LocationResult
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Manifest-registered receiver for periodic background location fixes
 * (see NativeLocationPingManager). Survives force-kill the same way
 * GeofenceBroadcastReceiver does — Play Services delivers fixes independent
 * of this app's process being alive.
 *
 * Posts directly to the SAME /child/location endpoint the foreground service
 * uses (matching LocationStateMachine._postChildLocation's payload shape), so
 * these pings flow through the normal processPointsForTrips() / QueueService /
 * TripStateMachine pipeline on the backend — no special-cased ingestion path.
 */
class LocationPingBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "LocationPingReceiver"
        const val ACTION_LOCATION_PING = "com.truenyx.naviqandroid.LOCATION_PING"
        private const val KEY_PENDING_QUEUE = "flutter.native_pending_location_pings"

        private fun isoFromMillis(millis: Long): String {
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            return fmt.format(Date(millis))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val result = LocationResult.extractResult(intent)
        if (intent.action == NearFenceBurst.ACTION_NEAR_FENCE_BURST) {
            handleNearFenceBurst(context, result)
            return
        }
        val location = result?.lastLocation
        if (location == null) {
            Log.w(TAG, "onReceive: no location in result, ignoring")
            return
        }

        val ageMs = System.currentTimeMillis() - location.time
        Log.i(TAG, "Native background location ping: ${location.latitude}, ${location.longitude} (fix age=${ageMs}ms)")
        NativeFileLogger.log(
            context, "LOCATION_PING",
            "received lat=${location.latitude} lng=${location.longitude} accuracy=${location.accuracy} ageMs=$ageMs"
        )

        val appContext = context.applicationContext
        val pendingResult = goAsync()

        Thread {
            try {
                flushPendingQueue(appContext)

                val childId = NativeApiClient.getChildId(appContext)
                if (childId.isNullOrEmpty()) {
                    Log.w(TAG, "No child_id available, dropping ping")
                    NativeFileLogger.log(appContext, "LOCATION_PING", "dropped: no child_id available")
                    return@Thread
                }

                val payload = JSONObject().apply {
                    put("child_id", childId)
                    put("lat", location.latitude)
                    put("lng", location.longitude)
                    put("accuracy", location.accuracy.toDouble())
                    put("accuracy_m", location.accuracy.toDouble())
                    // Unknown speed is omitted (speed_known=false), never sent as 0 m/s.
                    NativeLocationPayload.putSpeed(this, location.hasSpeed(), location.speed)
                    put("bearing", if (location.hasBearing()) location.bearing.toDouble() else 0.0)
                    put("altitude", if (location.hasAltitude()) location.altitude else 0.0)
                    put("battery", readBatteryPercent(appContext))
                    put("timestamp", isoFromMillis(location.time))
                    put("source", "android_native_background_ping")
                    NativeLocationPayload.putDiagnostics(appContext, this, "android_native_background_ping", "native_ping")
                }

                val posted = NativeApiClient.postJson(appContext, "child/location", payload)
                Log.i(TAG, "Location ping posted=$posted")
                NativeFileLogger.log(appContext, "LOCATION_PING", "post posted=$posted")
                if (!posted) {
                    enqueuePending(appContext, payload)
                }

                // The real service now owns precise tracking → drop any burst; otherwise,
                // if the child is near a saved place and only this fallback is running,
                // take a bounded high-accuracy burst (NearFenceBurst / NearFencePolicy).
                NearFenceBurst.cancelIfSuperseded(appContext)
                NearFenceBurst.maybeStart(appContext, location)
            } catch (e: Exception) {
                Log.e(TAG, "Error handling location ping: ${e.message}", e)
                NativeFileLogger.log(appContext, "LOCATION_PING", "ERROR ${e.message}")
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    /**
     * Deliveries of the bounded near-fence burst. Only a fresh (<= 20 s, monotonic
     * clock) and precise (<= 75 m) fix is posted — never a cached position — and
     * nothing is queued for later: a stale fix would be worthless as evidence.
     */
    private fun handleNearFenceBurst(context: Context, result: LocationResult?) {
        val fixes = result?.locations ?: return
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        Thread {
            try {
                if (TrackingRecovery.isHighAccuracyActive(appContext)) {
                    NearFenceBurst.cancel(appContext)
                    return@Thread
                }
                val childId = NativeApiClient.getChildId(appContext)
                if (childId.isNullOrEmpty()) {
                    NearFenceBurst.cancel(appContext)
                    return@Thread
                }
                for (fix in fixes) {
                    val age = NearFenceBurst.fixAgeMs(fix)
                    val accuracy = if (fix.hasAccuracy()) fix.accuracy.toDouble() else null
                    if (age == null || !NearFencePolicy.isUsableBurstFix(age, accuracy)) {
                        NativeFileLogger.log(appContext, "NEAR_FENCE_BURST", "discarded fix ageMs=$age accuracy=$accuracy")
                        continue
                    }
                    val payload = JSONObject().apply {
                        put("child_id", childId)
                        put("lat", fix.latitude)
                        put("lng", fix.longitude)
                        put("accuracy", fix.accuracy.toDouble())
                        put("accuracy_m", fix.accuracy.toDouble())
                        NativeLocationPayload.putSpeed(this, fix.hasSpeed(), fix.speed)
                        put("bearing", if (fix.hasBearing()) fix.bearing.toDouble() else 0.0)
                        put("battery", readBatteryPercent(appContext))
                        put("timestamp", isoFromMillis(fix.time))
                        NativeLocationPayload.putDiagnostics(appContext, this, "android_near_fence_burst", "native_burst")
                    }
                    val posted = NativeApiClient.postJson(appContext, "child/location", payload)
                    NativeFileLogger.log(appContext, "NEAR_FENCE_BURST", "post posted=$posted accuracy=$accuracy")
                }
            } catch (e: Exception) {
                NativeFileLogger.log(appContext, "NEAR_FENCE_BURST", "ERROR ${e.message}")
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun readBatteryPercent(context: Context): Int {
        return try {
            val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        } catch (e: Exception) {
            -1
        }
    }

    private fun enqueuePending(context: Context, payload: JSONObject) {
        val prefs = context.getSharedPreferences(NativeGeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING_QUEUE, "[]")
        val queue = try { JSONArray(raw) } catch (e: Exception) { JSONArray() }
        queue.put(payload)
        val trimmed = if (queue.length() > 20) {
            JSONArray().apply {
                for (i in (queue.length() - 20) until queue.length()) put(queue.get(i))
            }
        } else queue
        prefs.edit().putString(KEY_PENDING_QUEUE, trimmed.toString()).apply()
    }

    private fun flushPendingQueue(context: Context) {
        val prefs = context.getSharedPreferences(NativeGeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING_QUEUE, null) ?: return
        val queue = try { JSONArray(raw) } catch (e: Exception) { return }
        if (queue.length() == 0) return

        val stillPending = JSONArray()
        for (i in 0 until queue.length()) {
            val entry = queue.optJSONObject(i) ?: continue
            if (!NativeApiClient.postJson(context, "child/location", entry)) {
                stillPending.put(entry)
            }
        }
        prefs.edit().putString(KEY_PENDING_QUEUE, stillPending.toString()).apply()
    }
}
