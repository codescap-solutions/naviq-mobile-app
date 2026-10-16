package com.truenyx.naviqandroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeLocationPayloadTest {
    @Test fun `a fix without a speed reading is UNKNOWN, never zero`() {
        assertNull(NativeLocationPayload.knownSpeedMps(hasSpeed = false, speed = 0f))
        assertNull(NativeLocationPayload.knownSpeedMps(hasSpeed = false, speed = 3f))
    }

    @Test fun `invalid readings are unknown`() {
        assertNull(NativeLocationPayload.knownSpeedMps(true, -1f))
        assertNull(NativeLocationPayload.knownSpeedMps(true, Float.NaN))
        assertNull(NativeLocationPayload.knownSpeedMps(true, Float.POSITIVE_INFINITY))
    }

    @Test fun `a genuinely measured 0 m_s stays zero`() {
        assertEquals(0.0, NativeLocationPayload.knownSpeedMps(true, 0f)!!, 0.0)
    }

    @Test fun `a measured speed is passed through`() {
        assertEquals(1.5, NativeLocationPayload.knownSpeedMps(true, 1.5f)!!, 1e-6)
    }
}
