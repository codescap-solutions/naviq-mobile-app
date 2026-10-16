package com.truenyx.naviqandroid

import android.content.Context

/**
 * Native half of the "your phone's clock is wrong" signal.
 *
 * The backend refuses a location whose capture time is far from its own clock
 * only when it can PROVE the phone clock is off (`HTTP 400`, `error_code:
 * CLOCK_SKEW`, see utils/clockSkew.js). The child app's Dart layer turns that
 * answer into a prompt (ClockSkewMonitor); the native receivers post without the
 * Flutter engine, so they record the same verdict in the same SharedPreferences
 * keys and the prompt shows whichever layer saw it first.
 *
 * [interpret] is pure (no Android, no org.json) so it is unit-tested on the JVM.
 * Only `child/location` answers are interpreted: trip and geofence posts do not
 * carry the skew contract.
 */
object NativeClockSkew {
    /** Same keys as ClockSkewMonitor (Dart): shared_preferences stores them under `flutter.`. */
    const val KEY_DETECTED_AT = "flutter.clock_skew_detected_at_ms"
    const val KEY_OFFSET_S = "flutter.clock_skew_offset_s"
    const val LOCATION_PATH = "child/location"

    enum class Action { RAISE, CLEAR, NONE }

    data class Verdict(val action: Action, val offsetSeconds: Long? = null)

    private val ERROR_CODE = Regex("\"error_code\"\\s*:\\s*\"CLOCK_SKEW\"")
    private val OFFSET = Regex("\"clock_offset_seconds\"\\s*:\\s*(-?\\d+)")
    private val HISTORY_ONLY = Regex("\"history_only\"\\s*:\\s*true")
    private val DUPLICATE = Regex("\"duplicate\"\\s*:\\s*true")

    fun interpret(path: String, httpCode: Int, body: String?): Verdict {
        if (path != LOCATION_PATH || body == null) return Verdict(Action.NONE)
        if (httpCode == 400 && ERROR_CODE.containsMatchIn(body)) {
            return Verdict(Action.RAISE, OFFSET.find(body)?.groupValues?.get(1)?.toLongOrNull())
        }
        if (httpCode in 200..299) {
            // A delayed upload kept as history, or a duplicate retry, proves nothing about the clock.
            if (HISTORY_ONLY.containsMatchIn(body) || DUPLICATE.containsMatchIn(body)) return Verdict(Action.NONE)
            return Verdict(Action.CLEAR)
        }
        return Verdict(Action.NONE)
    }

    /** The few SharedPreferences operations the verdict needs — faked in JVM tests. */
    interface Store {
        fun contains(key: String): Boolean
        fun putLong(key: String, value: Long)
        fun remove(key: String)
    }

    /** Persist [verdict] into [store]. */
    fun applyTo(store: Store, verdict: Verdict, nowMs: Long) {
        when (verdict.action) {
            Action.RAISE -> {
                store.putLong(KEY_DETECTED_AT, nowMs)
                if (verdict.offsetSeconds != null) store.putLong(KEY_OFFSET_S, verdict.offsetSeconds) else store.remove(KEY_OFFSET_S)
            }
            Action.CLEAR -> if (store.contains(KEY_DETECTED_AT) || store.contains(KEY_OFFSET_S)) {
                store.remove(KEY_DETECTED_AT)
                store.remove(KEY_OFFSET_S)
            }
            Action.NONE -> Unit
        }
    }

    /** Interpret one answer and persist the verdict. Never throws: bookkeeping must not affect an upload. */
    fun handleResponse(store: Store, path: String, httpCode: Int, body: String?, nowMs: Long) {
        try {
            applyTo(store, interpret(path, httpCode, body), nowMs)
        } catch (_: Exception) {
        }
    }

    /**
     * Reads at most [max] characters, looping until end of stream: a single
     * `Reader.read` may return fewer characters than the body holds (chunked
     * responses), which could cut `error_code` off. Returns null for an empty body.
     */
    fun readBounded(reader: java.io.Reader, max: Int): String? {
        val sb = StringBuilder()
        val buf = CharArray(minOf(1024, max))
        while (sb.length < max) {
            val n = reader.read(buf, 0, minOf(buf.size, max - sb.length))
            if (n < 0) break
            sb.append(buf, 0, n)
        }
        return if (sb.isEmpty()) null else sb.toString()
    }

    /** Production store over the app's FlutterSharedPreferences file. */
    fun storeFor(context: Context): Store {
        val prefs = context.getSharedPreferences(NativeGeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
        return object : Store {
            override fun contains(key: String) = prefs.contains(key)
            override fun putLong(key: String, value: Long) { prefs.edit().putLong(key, value).apply() }
            override fun remove(key: String) { prefs.edit().remove(key).apply() }
        }
    }
}
