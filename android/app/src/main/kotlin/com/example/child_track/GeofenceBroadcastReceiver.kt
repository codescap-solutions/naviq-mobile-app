package com.truenyx.naviqandroid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.android.gms.tasks.Tasks
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Manifest-registered receiver for native Android geofence transitions.
 *
 * This is the piece that makes geofence detection survive a force-kill: Android
 * invokes a manifest-registered BroadcastReceiver for a matching PendingIntent
 * even when the app process (and any Dart isolate / foreground service) is
 * completely dead, giving it a short execution window to do work. It does NOT
 * spin up the Flutter engine — it POSTs to the backend directly via
 * NativeApiClient, using credentials mirrored into plain SharedPreferences by
 * the Dart side (see ChildRepo.syncAppGroupCredentials).
 */
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "GeofenceReceiver"
        const val ACTION_GEOFENCE_EVENT = "com.truenyx.naviqandroid.GEOFENCE_TRANSITION"
        private const val KEY_PENDING_QUEUE = "flutter.native_pending_geofence_events"

        private fun isoNow(): String {
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            return fmt.format(Date())
        }

        private fun isoAt(epochMs: Long): String {
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            return fmt.format(Date(epochMs))
        }

        /** Timeout for the fresh evidence fix taken right after a region callback. */
        private const val FRESH_FIX_TIMEOUT_MS = 6_000L

        /**
         * A region callback is only a HINT — the server confirms an ENTER/EXIT
         * from RELIABLE, FRESH location points (naviQ-server
         * geofenceEvidence.js). Take one high-accuracy fix right now and post
         * it, instead of leaving the server to wait for the next routine ping
         * (which in low-power mode can be minutes away). The fix's OWN capture
         * time is sent, never "now". Best-effort: failures are ignored — the
         * server's verification probe covers the gap.
         */
        private fun postFreshEvidenceFix(context: Context, childId: String, source: String) {
            try {
                val client = LocationServices.getFusedLocationProviderClient(context)
                val cts = CancellationTokenSource()
                val fix = Tasks.await(
                    client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token),
                    FRESH_FIX_TIMEOUT_MS,
                    TimeUnit.MILLISECONDS,
                ) ?: return
                val payload = JSONObject().apply {
                    put("child_id", childId)
                    put("lat", fix.latitude)
                    put("lng", fix.longitude)
                    put("accuracy_m", fix.accuracy.toDouble())
                    put("speed_mps", if (fix.hasSpeed()) fix.speed.toDouble() else 0.0)
                    put("bearing", if (fix.hasBearing()) fix.bearing.toDouble() else 0.0)
                    put("timestamp", isoAt(if (fix.time > 0) fix.time else System.currentTimeMillis()))
                    // Engineering diagnostics only.
                    put("platform", "android")
                    put("tracking_profile", "native_region")
                    put("fix_source", source)
                }
                val ok = NativeApiClient.postJson(context, "child/location", payload)
                Log.i(TAG, "fresh evidence fix posted=$ok acc=${fix.accuracy}m source=$source")
            } catch (e: Exception) {
                Log.w(TAG, "fresh evidence fix failed: ${e.message}")
            }
        }

        private fun transitionTypeToString(transition: Int): String = when (transition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "ENTER"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "EXIT"
            Geofence.GEOFENCE_TRANSITION_DWELL -> "DWELL"
            else -> "UNKNOWN"
        }

        /**
         * Cooldown window for flap suppression (see [isLikelyFlap]) — a child
         * standing right at a fence boundary can GPS-jitter across it,
         * producing ENTER→EXIT→ENTER within seconds. This only needs to
         * outlast the jitter, not the real detection latency (which is
         * already 2-5 minutes for native geofencing), so 45s is generous.
         */
        private const val FLAP_COOLDOWN_MS = 45_000L

        /**
         * True when [transitionType] for [geofenceId] flips back to the
         * opposite of the last transition posted for that same fence within
         * [FLAP_COOLDOWN_MS] — the signature of boundary GPS jitter, not a
         * real crossing. DWELL is exempt: Play Services already gates it
         * behind its own multi-minute loitering delay, so it can't flap.
         * A repeat of the SAME type is left alone (harmless either way).
         */
        private fun isLikelyFlap(
            context: Context,
            geofenceId: String,
            transitionType: String,
            now: Long,
        ): Boolean {
            if (transitionType == "DWELL") return false
            val prefs = context.getSharedPreferences(NativeGeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
            val lastType = prefs.getString("last_transition_type_$geofenceId", null) ?: return false
            val lastAt = prefs.getLong("last_transition_at_$geofenceId", 0L)
            return lastType != transitionType && (now - lastAt) < FLAP_COOLDOWN_MS
        }

        private fun recordTransition(context: Context, geofenceId: String, transitionType: String, now: Long) {
            if (transitionType == "DWELL") return
            val prefs = context.getSharedPreferences(NativeGeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putString("last_transition_type_$geofenceId", transitionType)
                .putLong("last_transition_at_$geofenceId", now)
                .apply()
        }

        /** Timeout for the single confirming fix requested by [shouldPostExit]. */
        private const val CONFIRM_FIX_TIMEOUT_MS = 15_000L

        /**
         * True when [fix]'s own accuracy circle overlaps the fence boundary —
         * i.e. the fix isn't precise enough to say which side of the fence the
         * device is actually on. This is the same distance math the fence
         * check itself already uses, just compared against accuracy instead
         * of a hard threshold.
         */
        private fun isAmbiguous(fix: Location, fenceLat: Double, fenceLng: Double, fenceRadius: Double): Boolean {
            val results = FloatArray(1)
            Location.distanceBetween(fix.latitude, fix.longitude, fenceLat, fenceLng, results)
            return kotlin.math.abs(results[0] - fenceRadius) <= fix.accuracy
        }

        private fun isOutsideFence(fix: Location, fenceLat: Double, fenceLng: Double, fenceRadius: Double): Boolean {
            val results = FloatArray(1)
            Location.distanceBetween(fix.latitude, fix.longitude, fenceLat, fenceLng, results)
            return results[0] > fenceRadius
        }

        /**
         * EXIT-only ambiguity check (see the LLM Council verdict this
         * implements: a false ENTER costs nothing, a false EXIT is the one
         * that spikes a parent's pulse, so only EXIT pays the confirmation
         * cost). Returns true if this EXIT should be posted, false if it
         * should be suppressed as likely GPS jitter.
         *
         * Only spends the extra GPS request when [triggeringFix]'s own
         * accuracy circle actually straddles the fence boundary — an
         * unambiguous fix (the common case) fires with zero added cost or
         * delay, unchanged from before this fix.
         */
        private fun shouldPostExit(
            context: Context,
            triggeringFix: Location?,
            fenceLat: Double,
            fenceLng: Double,
            fenceRadius: Double,
        ): Boolean {
            if (triggeringFix == null) return true // no fix to judge ambiguity with — fail open
            if (!isAmbiguous(triggeringFix, fenceLat, fenceLng, fenceRadius)) return true

            Log.i(TAG, "EXIT fix is ambiguous (accuracy=${triggeringFix.accuracy}m straddles boundary) — requesting confirming fix")
            val confirmFix = try {
                val client = LocationServices.getFusedLocationProviderClient(context)
                val cts = CancellationTokenSource()
                Tasks.await(
                    client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token),
                    CONFIRM_FIX_TIMEOUT_MS,
                    TimeUnit.MILLISECONDS,
                )
            } catch (e: Exception) {
                Log.w(TAG, "Confirming fix failed/timed out — posting original EXIT (fail open): ${e.message}")
                null
            }

            // Fail open on a failed/timed-out confirming fix too — an
            // ambiguous-but-unconfirmable EXIT might still be real, and
            // silently dropping it is worse than the jitter it might be.
            if (confirmFix == null) return true

            val stillOutside = isOutsideFence(confirmFix, fenceLat, fenceLng, fenceRadius)
            if (!stillOutside) {
                Log.i(TAG, "Confirming fix landed back inside the fence — suppressing as GPS jitter")
            }
            return stillOutside
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent)
        if (geofencingEvent == null) {
            Log.w(TAG, "onReceive: not a geofencing event intent, ignoring")
            return
        }

        if (geofencingEvent.hasError()) {
            val errorMessage = GeofenceStatusCodes.getStatusCodeString(geofencingEvent.errorCode)
            Log.e(TAG, "GeofencingEvent error: $errorMessage")
            return
        }

        val transitionType = transitionTypeToString(geofencingEvent.geofenceTransition)
        val triggeringIds = geofencingEvent.triggeringGeofences?.map { it.requestId } ?: emptyList()
        if (triggeringIds.isEmpty()) {
            Log.w(TAG, "onReceive: no triggering geofences in event")
            return
        }

        Log.i(TAG, "Geofence transition $transitionType for: $triggeringIds")
        val names = triggeringIds.joinToString(", ") { "$it(${NativeGeofenceManager.getGeofenceName(context, it)})" }
        NativeFileLogger.log(context, "GEOFENCE", "received transition=$transitionType ids=$names")

        // The fix that actually triggered this transition — used by the EXIT
        // ambiguity check below. Read here (still on the calling thread) since
        // it's just a field on the already-parsed event, no I/O.
        val triggeringFix = geofencingEvent.triggeringLocation

        // BroadcastReceiver.onReceive gets a very short window (~10s) and must not
        // block on network I/O directly — goAsync() extends that window slightly
        // and lets us finish the work on a background thread.
        val pendingResult = goAsync()
        val appContext = context.applicationContext

        Thread {
            try {
                // Best-effort: flush anything queued from a previous failed attempt first.
                flushPendingQueue(appContext)

                val childId = NativeApiClient.getChildId(appContext)
                if (childId.isNullOrEmpty()) {
                    Log.w(TAG, "No child_id available, dropping geofence event(s)")
                    NativeFileLogger.log(appContext, "GEOFENCE", "dropped: no child_id available")
                    return@Thread
                }

                // Only fetched/used for EXIT (see shouldPostExit) — cheap to build
                // once here regardless, from the already-persisted fence cache.
                val fenceDefs = NativeGeofenceManager.getPersistedGeofences(appContext)
                    .associateBy { it["id"] as? String }

                val timestamp = isoNow()
                val now = System.currentTimeMillis()
                var reportedAny = false
                for (geofenceId in triggeringIds) {
                    if (transitionType == "EXIT") {
                        val fence = fenceDefs[geofenceId]
                        val fenceLat = fence?.get("lat") as? Double
                        val fenceLng = fence?.get("lng") as? Double
                        val fenceRadius = fence?.get("radius") as? Double
                        if (fenceLat != null && fenceLng != null && fenceRadius != null &&
                            !shouldPostExit(appContext, triggeringFix, fenceLat, fenceLng, fenceRadius)
                        ) {
                            NativeFileLogger.log(
                                appContext, "GEOFENCE",
                                "suppressed ambiguous EXIT id=$geofenceId (confirming fix stayed inside — GPS jitter)"
                            )
                            continue
                        }
                    }

                    if (isLikelyFlap(appContext, geofenceId, transitionType, now)) {
                        Log.i(TAG, "Suppressed likely GPS-jitter flap: $transitionType on $geofenceId")
                        NativeFileLogger.log(
                            appContext, "GEOFENCE",
                            "suppressed flap transition=$transitionType id=$geofenceId"
                        )
                        continue
                    }
                    recordTransition(appContext, geofenceId, transitionType, now)

                    val payload = JSONObject().apply {
                        put("childId", childId)
                        put("geofenceId", geofenceId)
                        put("eventType", transitionType)
                        put("timestamp", timestamp)
                        put("source", "android_native_geofence")
                    }
                    val posted = NativeApiClient.postJson(appContext, "child/geofence-event", payload)
                    Log.i(TAG, "postGeofenceEvent: posted=$posted for $transitionType on $geofenceId")
                    NativeFileLogger.log(
                        appContext, "GEOFENCE",
                        "post transition=$transitionType id=$geofenceId ts=$timestamp posted=$posted"
                    )
                    if (!posted) {
                        enqueuePending(appContext, payload)
                    }
                    reportedAny = true
                }

                // Hint → evidence: post a fresh accurate fix right away.
                if (reportedAny && (transitionType == "ENTER" || transitionType == "EXIT")) {
                    postFreshEvidenceFix(appContext, childId, "region_${transitionType.lowercase(Locale.US)}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling geofence event: ${e.message}", e)
                NativeFileLogger.log(appContext, "GEOFENCE", "ERROR ${e.message}")
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun enqueuePending(context: Context, payload: JSONObject) {
        val prefs = context.getSharedPreferences(NativeGeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING_QUEUE, "[]")
        val queue = try { JSONArray(raw) } catch (e: Exception) { JSONArray() }
        queue.put(payload)
        // Cap the queue so a prolonged outage can't grow this unbounded.
        val trimmed = if (queue.length() > 50) {
            JSONArray().apply {
                for (i in (queue.length() - 50) until queue.length()) put(queue.get(i))
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
            if (!NativeApiClient.postJson(context, "child/geofence-event", entry)) {
                stillPending.put(entry)
            }
        }
        prefs.edit().putString(KEY_PENDING_QUEUE, stillPending.toString()).apply()
    }
}
