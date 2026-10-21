package com.truenyx.naviqandroid

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONObject

/**
 * Native geofencing wrapper — the Android analog of IOSNativeGeofenceManager.swift.
 *
 * Registration lives in Play Services (GeofencingClient), independent of this
 * app's process — Android allows up to 100 simultaneously monitored geofences
 * (vs iOS's 20). Transitions are delivered to [GeofenceBroadcastReceiver] via a
 * manifest-registered PendingIntent, which the OS can invoke even after the
 * user has force-killed the app (unlike the Dart LocalGeofenceEngine, which
 * only runs while the foreground service's Dart isolate is alive).
 */
object NativeGeofenceManager {
    private const val TAG = "NativeGeofenceManager"
    const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_GEOFENCE_MAP = "flutter.native_geofence_map" // JSON: id -> {name, lat, lng, radius, priority}
    /** JSON: id -> signature of the fence as last SUCCESSFULLY registered (see GeofenceRegistrationDiff). */
    private const val KEY_REGISTERED_SIGNATURES = "flutter.native_geofence_registered_sig"
    private const val MAX_GEOFENCES = 100 // Android's documented per-app limit
    private const val DWELL_LOITERING_DELAY_MS = 5 * 60 * 1000 // 5 min — matches iOS dwell threshold
    private const val REQUEST_CODE = 4471

    private fun geofencingClient(context: Context) =
        LocationServices.getGeofencingClient(context.applicationContext)

    private fun geofencePendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java).apply {
            action = GeofenceBroadcastReceiver.ACTION_GEOFENCE_EVENT
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getBroadcast(context.applicationContext, REQUEST_CODE, intent, flags)
    }

    /**
     * Replace the registered geofence set (remove-then-readd) on the existing
     * periodic cadence (~10 min Dart refresh, 15 min watchdog). Registration is
     * diff-aware: only NEW or EDITED fences are added with an initial ENTER
     * trigger; unchanged fences are re-armed with no initial trigger so a
     * periodic sync can no longer fabricate an ENTER hint for a child who is
     * simply sitting inside a place (see GeofenceRegistrationDiff).
     */
    fun syncGeofences(context: Context, geofences: List<Map<String, Any?>>) {
        val client = geofencingClient(context)
        val pendingIntent = geofencePendingIntent(context)

        val sorted = geofences
            .sortedWith(compareBy({ (it["priority"] as? Int) ?: 5 }, { (it["id"] as? String) ?: "" }))
            .take(MAX_GEOFENCES)

        persistGeofenceMap(context, sorted)

        client.removeGeofences(pendingIntent).addOnCompleteListener {
            if (sorted.isEmpty()) {
                Log.i(TAG, "No geofences to register")
                NativeFileLogger.log(context, "GEOFENCE_SYNC", "no geofences to register")
                saveRegisteredSignatures(context, emptyMap())
                return@addOnCompleteListener
            }

            // Only NEW or EDITED fences keep the initial ENTER trigger; unchanged
            // ones are re-armed silently (see GeofenceRegistrationDiff for why).
            val defs = sorted.mapNotNull { fence ->
                val id = fence["id"] as? String ?: return@mapNotNull null
                val lat = (fence["lat"] as? Number)?.toDouble() ?: return@mapNotNull null
                val lng = (fence["lng"] as? Number)?.toDouble() ?: return@mapNotNull null
                val radius = (fence["radius"] as? Number)?.toDouble() ?: 150.0
                GeofenceRegistrationDiff.Fence(id, lat, lng, radius)
            }
            val plan = GeofenceRegistrationDiff.plan(loadRegisteredSignatures(context), defs)

            val registered = mutableMapOf<String, String>()
            val pending = java.util.concurrent.atomic.AtomicInteger(0)
            val finishGroup = {
                if (pending.decrementAndGet() == 0) saveRegisteredSignatures(context, registered)
            }
            val groups = GeofenceRegistrationDiff.groups(plan)
            if (groups.isEmpty()) return@addOnCompleteListener
            pending.set(groups.size)

            for ((group, initialTrigger) in groups.map { it.fences to it.initialTrigger }) {
                try {
                    val geofenceObjects = group.map { f ->
                        Geofence.Builder()
                            .setRequestId(f.id)
                            .setCircularRegion(f.lat, f.lng, f.radiusM.toFloat())
                            .setExpirationDuration(Geofence.NEVER_EXPIRE)
                            .setTransitionTypes(
                                Geofence.GEOFENCE_TRANSITION_ENTER or
                                    Geofence.GEOFENCE_TRANSITION_EXIT or
                                    Geofence.GEOFENCE_TRANSITION_DWELL
                            )
                            .setLoiteringDelay(DWELL_LOITERING_DELAY_MS)
                            .build()
                    }
                    val request = try {
                        GeofencingRequest.Builder()
                            .setInitialTrigger(initialTrigger)
                            .addGeofences(geofenceObjects)
                            .build()
                    } catch (e: IllegalArgumentException) {
                        if (initialTrigger != 0) throw e
                        // "No initial trigger" rejected by this Play Services version: fall back to
                        // DWELL-only (timeline-only on the server; never an arrival notification).
                        GeofencingRequest.Builder()
                            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_DWELL)
                            .addGeofences(geofenceObjects)
                            .build()
                    }
                    client.addGeofences(request, pendingIntent)
                        .addOnSuccessListener {
                            group.forEach { registered[it.id] = GeofenceRegistrationDiff.signature(it) }
                            Log.i(TAG, "Registered ${group.size} native Android geofences (initialTrigger=$initialTrigger)")
                            NativeFileLogger.log(
                                context, "GEOFENCE_SYNC",
                                "registered ${group.size} initialTrigger=$initialTrigger: " +
                                    group.joinToString(", ") { "${it.id}(${getGeofenceName(context, it.id)})" }
                            )
                            finishGroup()
                        }
                        .addOnFailureListener { e ->
                            Log.e(TAG, "Failed to register geofences: ${e.message}", e)
                            NativeFileLogger.log(context, "GEOFENCE_SYNC", "FAILED to register: ${e.message}")
                            finishGroup()
                        }
                } catch (e: SecurityException) {
                    // GeofencingClient requires ACCESS_FINE_LOCATION at minimum.
                    Log.e(TAG, "Missing location permission for geofencing: ${e.message}")
                    NativeFileLogger.log(context, "GEOFENCE_SYNC", "SecurityException: ${e.message}")
                    finishGroup()
                } catch (e: IllegalArgumentException) {
                    Log.e(TAG, "Invalid geofence request (initialTrigger=$initialTrigger): ${e.message}")
                    NativeFileLogger.log(context, "GEOFENCE_SYNC", "IllegalArgument (initialTrigger=$initialTrigger): ${e.message}")
                    finishGroup()
                }
            }
        }
    }

    private fun loadRegisteredSignatures(context: Context): Map<String, String> {
        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_REGISTERED_SIGNATURES, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            json.keys().asSequence().associateWith { json.getString(it) }
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun saveRegisteredSignatures(context: Context, sigs: Map<String, String>) {
        val json = JSONObject()
        sigs.forEach { (k, v) -> json.put(k, v) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_REGISTERED_SIGNATURES, json.toString()).apply()
    }

    /**
     * Persists the full fence definitions (not just id->name) so
     * [getPersistedGeofences] can hand them straight back to [syncGeofences] —
     * this is what lets [LocationWatchdogWorker] re-register geofences
     * periodically without needing the Dart isolate alive to supply the list,
     * guarding against Play Services silently dropping the registration
     * (a known real-world occurrence, same rationale as the location-ping
     * watchdog).
     */
    private fun persistGeofenceMap(context: Context, fences: List<Map<String, Any?>>) {
        val json = JSONObject()
        for (fence in fences) {
            val id = fence["id"] as? String ?: continue
            val entry = JSONObject()
            entry.put("name", fence["name"] as? String ?: "Unknown")
            entry.put("lat", (fence["lat"] as? Number)?.toDouble())
            entry.put("lng", (fence["lng"] as? Number)?.toDouble())
            entry.put("radius", (fence["radius"] as? Number)?.toDouble() ?: 150.0)
            entry.put("priority", (fence["priority"] as? Int) ?: 5)
            json.put(id, entry)
        }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_GEOFENCE_MAP, json.toString()).apply()
    }

    fun getGeofenceName(context: Context, id: String): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_GEOFENCE_MAP, null) ?: return "Unknown"
        return try {
            JSONObject(raw).optJSONObject(id)?.optString("name", "Unknown") ?: "Unknown"
        } catch (e: Exception) {
            "Unknown"
        }
    }

    /** Reconstructs the last-synced fence list from persisted storage, in the
     * same shape [syncGeofences] expects — used by [LocationWatchdogWorker] to
     * re-register without a live Dart isolate. Returns empty if nothing has
     * been synced yet (e.g. before first login) or the JSON was written by an
     * older app version whose entries lack lat/lng.
     */
    fun getPersistedGeofences(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_GEOFENCE_MAP, null) ?: return emptyList()
        return try {
            val json = JSONObject(raw)
            val result = mutableListOf<Map<String, Any?>>()
            json.keys().forEach { id ->
                val entry = json.optJSONObject(id) ?: return@forEach
                if (!entry.has("lat") || !entry.has("lng")) return@forEach
                result.add(
                    mapOf(
                        "id" to id,
                        "name" to entry.optString("name", "Unknown"),
                        "lat" to entry.optDouble("lat"),
                        "lng" to entry.optDouble("lng"),
                        "radius" to entry.optDouble("radius", 150.0),
                        "priority" to entry.optInt("priority", 5)
                    )
                )
            }
            result
        } catch (e: Exception) {
            emptyList()
        }
    }
}
