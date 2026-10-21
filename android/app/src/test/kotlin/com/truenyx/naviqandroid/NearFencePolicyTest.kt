package com.truenyx.naviqandroid

import com.truenyx.naviqandroid.NearFencePolicy.BurstInputs
import com.truenyx.naviqandroid.NearFencePolicy.Fence
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NearFencePolicyTest {
    // ~111 m per 0.001° latitude
    private val home = Fence(11.2500, 75.7800, 100.0)
    private fun north(metres: Double) = 11.2500 + metres / 111_195.0

    @Test fun `nearest edge is signed - negative inside, positive outside`() {
        assertTrue(NearFencePolicy.nearestEdgeM(home.lat, home.lng, listOf(home))!! < 0)
        val out = NearFencePolicy.nearestEdgeM(north(400.0), home.lng, listOf(home))!!
        assertEquals(300.0, out, 3.0)
        assertNull(NearFencePolicy.nearestEdgeM(1.0, 1.0, emptyList()))
    }

    @Test fun `near boundary on both sides, not far away, not deep inside`() {
        val acc = 50.0
        assertTrue(NearFencePolicy.isNearBoundary(north(250.0), home.lng, acc, listOf(home)))   // approaching
        assertTrue(NearFencePolicy.isNearBoundary(north(90.0), home.lng, acc, listOf(home)))    // just inside the edge
        assertFalse(NearFencePolicy.isNearBoundary(north(2_000.0), home.lng, acc, listOf(home))) // far
        assertFalse(NearFencePolicy.isNearBoundary(home.lat, home.lng, acc, listOf(home)))       // centre of a 100 m fence
        assertFalse(NearFencePolicy.isNearBoundary(north(10.0), home.lng, acc, listOf(Fence(11.25, 75.78, 500.0)))) // deep inside a big fence
    }

    @Test fun `no reliable proximity from a missing or very coarse fix - no invented distance`() {
        assertFalse(NearFencePolicy.isNearBoundary(north(250.0), home.lng, null, listOf(home)))
        assertFalse(NearFencePolicy.isNearBoundary(north(250.0), home.lng, 0.0, listOf(home)))
        assertFalse(NearFencePolicy.isNearBoundary(north(250.0), home.lng, 5_000.0, listOf(home)))
        assertFalse(NearFencePolicy.isNearBoundary(north(250.0), home.lng, 50.0, emptyList()))
    }

    private val base = BurstInputs(highAccuracyActive = false, nearBoundary = true, nowMs = 1_000_000, activeUntilMs = 0, lastBurstStartMs = 0)

    @Test fun `near-fence activation when only the fallback is running`() =
        assertTrue(NearFencePolicy.shouldStartBurst(base))

    @Test fun `no burst while the real foreground service is active (no duplicate stream)`() =
        assertFalse(NearFencePolicy.shouldStartBurst(base.copy(highAccuracyActive = true)))

    @Test fun `no burst away from a boundary`() =
        assertFalse(NearFencePolicy.shouldStartBurst(base.copy(nearBoundary = false)))

    @Test fun `duplicate trigger while a burst is active is ignored`() =
        assertFalse(NearFencePolicy.shouldStartBurst(base.copy(activeUntilMs = base.nowMs + 60_000, lastBurstStartMs = base.nowMs - 60_000)))

    @Test fun `burst expiry then cooldown, then it may start again`() {
        val ended = base.copy(activeUntilMs = base.nowMs - 1, lastBurstStartMs = base.nowMs - NearFencePolicy.BURST_DURATION_MS - 1)
        assertFalse("still cooling down", NearFencePolicy.shouldStartBurst(ended))
        val later = ended.copy(nowMs = ended.lastBurstStartMs + NearFencePolicy.COOLDOWN_MS + 1)
        assertTrue(NearFencePolicy.shouldStartBurst(later))
    }

    @Test fun `burst is bounded in time, updates and interval`() {
        assertTrue(NearFencePolicy.BURST_DURATION_MS <= 3 * 60_000)
        assertTrue(NearFencePolicy.BURST_MAX_UPDATES <= 10)
        assertTrue(NearFencePolicy.BURST_MIN_INTERVAL_MS >= 5_000)
        assertTrue(NearFencePolicy.COOLDOWN_MS >= 5 * 60_000)
    }

    @Test fun `only fresh and precise fixes are usable - never a cached or coarse one`() {
        assertTrue(NearFencePolicy.isUsableBurstFix(2_000, 20.0))
        assertTrue(NearFencePolicy.isUsableBurstFix(0, 75.0))
        assertFalse("cached", NearFencePolicy.isUsableBurstFix(60_000, 10.0))
        assertFalse("coarse", NearFencePolicy.isUsableBurstFix(1_000, 100.0))
        assertFalse("unknown accuracy", NearFencePolicy.isUsableBurstFix(1_000, null))
        assertFalse("zero accuracy is unknown, not perfect", NearFencePolicy.isUsableBurstFix(1_000, 0.0))
        assertFalse("future-dated", NearFencePolicy.isUsableBurstFix(-1, 10.0))
    }

    @Test fun `the policy never relaxes the server accuracy limit`() =
        assertNotNull(NearFencePolicy.MAX_FIX_ACCURACY_M.takeIf { it <= 75.0 })
}
