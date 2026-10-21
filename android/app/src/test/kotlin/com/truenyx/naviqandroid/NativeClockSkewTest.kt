package com.truenyx.naviqandroid

import com.truenyx.naviqandroid.NativeClockSkew.Action
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeClockSkewTest {
    private val skewBody =
        """{"is_success":false,"message":"Location timestamp is too far from server time","error_code":"CLOCK_SKEW","data":{"server_time":"2026-10-10T10:00:00.000Z","clock_offset_seconds":1200}}"""

    @Test fun `a CLOCK_SKEW 400 on a location post raises the prompt with the reported offset`() {
        val v = NativeClockSkew.interpret("child/location", 400, skewBody)
        assertEquals(Action.RAISE, v.action)
        assertEquals(1200L, v.offsetSeconds)
    }

    @Test fun `a phone that is ahead reports a negative offset`() {
        val v = NativeClockSkew.interpret("child/location", 400, skewBody.replace("1200", "-1500"))
        assertEquals(Action.RAISE, v.action)
        assertEquals(-1500L, v.offsetSeconds)
    }

    @Test fun `whitespace in the JSON does not matter`() {
        val body = "{ \"error_code\" : \"CLOCK_SKEW\", \"data\": { \"clock_offset_seconds\" : 900 } }"
        assertEquals(900L, NativeClockSkew.interpret("child/location", 400, body).offsetSeconds)
    }

    @Test fun `a missing offset still raises, with unknown offset`() {
        val v = NativeClockSkew.interpret("child/location", 400, """{"error_code":"CLOCK_SKEW"}""")
        assertEquals(Action.RAISE, v.action)
        assertNull(v.offsetSeconds)
    }

    @Test fun `other 400s never raise the clock prompt`() {
        for (code in listOf("TOO_OLD", "FUTURE_TIMESTAMP", "INVALID_TIMESTAMP")) {
            assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 400, """{"error_code":"$code"}""").action)
        }
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 400, """{"message":"child_id required"}""").action)
    }

    @Test fun `CLOCK_SKEW text on a non-400 is ignored`() {
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 500, skewBody).action)
    }

    @Test fun `an accepted live point clears the prompt`() {
        assertEquals(Action.CLEAR, NativeClockSkew.interpret("child/location", 200, """{"is_success":true,"message":"Location saved"}""").action)
        assertEquals(Action.CLEAR, NativeClockSkew.interpret("child/location", 201, """{"is_success":true,"data":{}}""").action)
    }

    @Test fun `a delayed offline replay (history_only) neither raises nor clears`() {
        val body = """{"is_success":true,"message":"Location saved","data":{"history_only":true,"reason":"DELAYED"}}"""
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 200, body).action)
    }

    @Test fun `a duplicate retry neither raises nor clears`() {
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 200, """{"is_success":true,"data":{"duplicate":true}}""").action)
    }

    @Test fun `network failure, 5xx, 401 and an unreadable body change nothing`() {
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", -1, null).action)
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 503, "x").action)
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 401, "x").action)
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/location", 200, null).action)
    }

    @Test fun `only location posts carry the skew contract`() {
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/geofence-event", 400, skewBody).action)
        assertEquals(Action.NONE, NativeClockSkew.interpret("child/geofence-event", 200, """{"is_success":true}""").action)
    }

    @Test fun `the keys match the Dart ClockSkewMonitor (flutter prefix)`() {
        assertEquals("flutter.clock_skew_detected_at_ms", NativeClockSkew.KEY_DETECTED_AT)
        assertEquals("flutter.clock_skew_offset_s", NativeClockSkew.KEY_OFFSET_S)
    }

    private class FakeStore : NativeClockSkew.Store {
        val values = mutableMapOf<String, Long>()
        var writes = 0
        override fun contains(key: String) = values.containsKey(key)
        override fun putLong(key: String, value: Long) { values[key] = value; writes++ }
        override fun remove(key: String) { values.remove(key); writes++ }
    }

    @Test fun `a skew refusal is persisted under the Dart keys as Longs`() {
        val s = FakeStore()
        NativeClockSkew.handleResponse(s, "child/location", 400, skewBody, nowMs = 1_700_000_000_000L)
        assertEquals(1_700_000_000_000L, s.values[NativeClockSkew.KEY_DETECTED_AT])
        assertEquals(1200L, s.values[NativeClockSkew.KEY_OFFSET_S])
    }

    @Test fun `an unknown offset removes a stale offset instead of keeping an old one`() {
        val s = FakeStore().apply { values[NativeClockSkew.KEY_OFFSET_S] = 900L }
        NativeClockSkew.handleResponse(s, "child/location", 400, """{"error_code":"CLOCK_SKEW"}""", nowMs = 5L)
        assertEquals(5L, s.values[NativeClockSkew.KEY_DETECTED_AT])
        assertNull(s.values[NativeClockSkew.KEY_OFFSET_S])
    }

    @Test fun `an accepted live point removes the verdict`() {
        val s = FakeStore()
        NativeClockSkew.handleResponse(s, "child/location", 400, skewBody, nowMs = 5L)
        NativeClockSkew.handleResponse(s, "child/location", 200, """{"is_success":true}""", nowMs = 6L)
        assertEquals(emptyMap<String, Long>(), s.values)
    }

    @Test fun `clearing with nothing stored writes nothing (no churn on every healthy post)`() {
        val s = FakeStore()
        NativeClockSkew.handleResponse(s, "child/location", 200, """{"is_success":true}""", nowMs = 6L)
        assertEquals(0, s.writes)
    }

    @Test fun `history-only replays and failures leave the stored verdict untouched`() {
        val s = FakeStore()
        NativeClockSkew.handleResponse(s, "child/location", 400, skewBody, nowMs = 5L)
        val before = s.values.toMap()
        NativeClockSkew.handleResponse(s, "child/location", 200, """{"is_success":true,"data":{"history_only":true}}""", nowMs = 9L)
        NativeClockSkew.handleResponse(s, "child/location", 503, "x", nowMs = 9L)
        NativeClockSkew.handleResponse(s, "child/location", -1, null, nowMs = 9L)
        assertEquals(before, s.values)
    }

    @Test fun `a store that throws never breaks the upload`() {
        val boom = object : NativeClockSkew.Store {
            override fun contains(key: String) = throw IllegalStateException("x")
            override fun putLong(key: String, value: Long) = throw IllegalStateException("x")
            override fun remove(key: String) = throw IllegalStateException("x")
        }
        NativeClockSkew.handleResponse(boom, "child/location", 400, skewBody, nowMs = 1L)
        NativeClockSkew.handleResponse(boom, "child/location", 200, "{}", nowMs = 1L)
    }

    /** A Reader that hands out one character per read(), like a slow chunked response. */
    private class Trickle(private val text: String) : java.io.Reader() {
        private var i = 0
        override fun read(cbuf: CharArray, off: Int, len: Int): Int {
            if (i >= text.length) return -1
            cbuf[off] = text[i++]
            return 1
        }
        override fun close() {}
    }

    @Test fun `a body delivered in tiny pieces is still read whole, so error_code is not cut off`() {
        val body = NativeClockSkew.readBounded(Trickle(skewBody), 4096)
        assertEquals(skewBody, body)
        assertEquals(Action.RAISE, NativeClockSkew.interpret("child/location", 400, body).action)
    }

    @Test fun `reading is bounded and an empty body is null`() {
        assertEquals(10, NativeClockSkew.readBounded(java.io.StringReader("x".repeat(100)), 10)!!.length)
        assertNull(NativeClockSkew.readBounded(java.io.StringReader(""), 4096))
    }
}
