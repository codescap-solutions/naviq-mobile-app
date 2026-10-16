package com.truenyx.naviqandroid

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Shared native HTTP client for background receivers (geofence transitions,
 * location pings) that must POST to the backend without the Flutter engine
 * running. Reads credentials mirrored into plain SharedPreferences by Dart
 * (see ChildRepo.syncAppGroupCredentials).
 */
object NativeApiClient {
    private const val PREFS_NAME = NativeGeofenceManager.PREFS_NAME
    private const val KEY_AUTH_TOKEN = "flutter.native_auth_token"
    private const val KEY_CHILD_ID = "flutter.child_id"
    const val DEFAULT_API_BASE = "https://naviq-server.codescap.com/api/v1/"
    private const val CONNECT_TIMEOUT_MS = 6000
    private const val READ_TIMEOUT_MS = 6000

    fun getChildId(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_CHILD_ID, null)
    }

    private fun getAuthToken(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_AUTH_TOKEN, null)
    }

    /** Delay before a single 401 retry — see [postJson]. */
    private const val AUTH_RETRY_DELAY_MS = 2000L

    /**
     * POST JSON to `${DEFAULT_API_BASE}$path`. Returns true if the request was
     * actually processed by the app (2xx success, or a non-401 4xx — a
     * validation rejection that would just repeat forever, not worth
     * retrying). Returns false — worth retrying later, via the caller's own
     * pending-queue — for network/timeout failures, 5xx server errors, and a
     * 401 that didn't clear after one retry.
     *
     * 401 used to be lumped in with "non-401 4xx" (`responseCode < 500`) and
     * counted as posted — silently and *permanently* discarding the event,
     * since callers only enqueue for retry when this returns false. That was
     * wrong specifically for 401: child sessions have no refresh_token and
     * their JWTs don't expire by design (see dio_client.dart's onError
     * handler for the Dart-side version of this same fix), so a 401 reaching
     * this native, engine-less path is almost always a token-read race —
     * this receiver read SharedPreferences at the exact moment the Dart side
     * was mid-write to the same key (ChildRepo.syncAppGroupCredentials), not
     * a genuinely dead session. One retry after a short delay, re-reading
     * whatever token is current by then, covers that race without treating
     * an actually-invalid 400/403/404/etc. as retryable forever.
     */
    fun postJson(context: Context, path: String, payload: JSONObject): Boolean {
        val token = getAuthToken(context)
        if (token.isNullOrEmpty()) return false

        stampDeviceTime(path, payload)
        val first = doPost(path, token, payload)
        NativeClockSkew.handleResponse(NativeClockSkew.storeFor(context), path, first.code, first.body, System.currentTimeMillis())
        if (first.code != 401) return first.code in 200 until 500

        Thread.sleep(AUTH_RETRY_DELAY_MS)
        val retryToken = getAuthToken(context)
        if (retryToken.isNullOrEmpty()) return false
        stampDeviceTime(path, payload)
        val retry = doPost(path, retryToken, payload)
        NativeClockSkew.handleResponse(NativeClockSkew.storeFor(context), path, retry.code, retry.body, System.currentTimeMillis())
        return retry.code in 200..299
    }

    /**
     * Location posts carry the device's wall clock at SEND time (refreshed on every
     * attempt, also for entries replayed from the pending queue), so the backend
     * can tell a wrong phone clock from a genuinely late upload.
     */
    private fun stampDeviceTime(path: String, payload: JSONObject) {
        if (!carriesDeviceTime(path)) return
        payload.put("device_time", deviceTimeIso(System.currentTimeMillis()))
    }

    /** Posts that carry the send-time stamp (the geofence-event contract ignores it today; see ChildRepo.postGeofenceEvent). */
    private val DEVICE_TIME_PATHS = setOf("child/location", "child/geofence-event")

    /** True for the posts that get a send-time `device_time` (never a capture-time field). */
    fun carriesDeviceTime(path: String): Boolean = DEVICE_TIME_PATHS.contains(path)

    fun deviceTimeIso(epochMs: Long): String {
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return fmt.format(java.util.Date(epochMs))
    }

    /** One POST attempt's outcome: the HTTP status (or -1 on a network/timeout exception) and a bounded copy of the body. */
    private class PostResult(val code: Int, val body: String?)

    private const val MAX_BODY_CHARS = 4096

    /** Fires one POST attempt. */
    private fun doPost(path: String, token: String, payload: JSONObject): PostResult {
        var connection: HttpURLConnection? = null
        return try {
            val url = URL(DEFAULT_API_BASE + path)
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
            }
            connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            // Only the location contract needs the answer's body (CLOCK_SKEW / history_only).
            PostResult(code, if (path == NativeClockSkew.LOCATION_PATH) readBody(connection, code) else null)
        } catch (e: Exception) {
            PostResult(-1, null)
        } finally {
            connection?.disconnect()
        }
    }

    private fun readBody(connection: HttpURLConnection, code: Int): String? = try {
        val stream = if (code >= 400) connection.errorStream else connection.inputStream
        stream?.bufferedReader(Charsets.UTF_8)?.use { r -> NativeClockSkew.readBounded(r, MAX_BODY_CHARS) }
    } catch (_: Exception) {
        null
    }
}
