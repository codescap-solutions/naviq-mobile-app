package com.truenyx.naviqandroid

import com.truenyx.naviqandroid.TrackingRecovery.Decision
import com.truenyx.naviqandroid.TrackingRecovery.Reason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackingRecoveryDecisionTest {
    private fun inputs(
        sdk: Int = 34,
        child: Boolean = true,
        fine: Boolean = true,
        bg: Boolean = true,
        running: Boolean = false,
        since: Long? = null,
        lastFailed: Boolean = false,
        reason: Reason = Reason.BOOT,
    ) = TrackingRecovery.Inputs(sdk, child, fine, bg, running, since, lastFailed, reason)

    @Test fun `every eligible event on a stopped service starts it`() {
        for (r in Reason.values()) assertEquals(Decision.START, TrackingRecovery.decide(inputs(reason = r)))
    }

    @Test fun `not a logged-in child device never starts`() =
        assertEquals(Decision.SKIP_NOT_CHILD, TrackingRecovery.decide(inputs(child = false)))

    @Test fun `missing fine location permission never starts`() =
        assertEquals(Decision.SKIP_NO_LOCATION_PERMISSION, TrackingRecovery.decide(inputs(fine = false)))

    @Test fun `Android 10+ without background location does not pretend to recover`() {
        assertEquals(Decision.SKIP_NO_BACKGROUND_LOCATION, TrackingRecovery.decide(inputs(sdk = 29, bg = false)))
        assertEquals(Decision.SKIP_NO_BACKGROUND_LOCATION, TrackingRecovery.decide(inputs(sdk = 36, bg = false)))
    }

    @Test fun `Android 9 and below do not need a separate background grant`() =
        assertEquals(Decision.START, TrackingRecovery.decide(inputs(sdk = 28, bg = false)))

    @Test fun `already running is never started twice`() =
        assertEquals(Decision.SKIP_ALREADY_RUNNING, TrackingRecovery.decide(inputs(running = true)))

    @Test fun `a second attempt within a minute is refused (no repeated starts or duplicate notifications)`() {
        assertEquals(Decision.SKIP_RECENT_ATTEMPT, TrackingRecovery.decide(inputs(since = 10_000)))
        assertEquals(Decision.START, TrackingRecovery.decide(inputs(since = TrackingRecovery.MIN_GAP_MS + 1)))
    }

    @Test fun `after a refused watchdog start the watchdog backs off for ten minutes`() {
        val failedWatchdog = inputs(reason = Reason.WATCHDOG, lastFailed = true)
        assertEquals(Decision.SKIP_RECENT_ATTEMPT, TrackingRecovery.decide(failedWatchdog.copy(msSinceLastAttempt = 5 * 60_000)))
        assertEquals(Decision.START, TrackingRecovery.decide(failedWatchdog.copy(msSinceLastAttempt = 11 * 60_000)))
    }

    @Test fun `a failed watchdog start does not block an event-driven attempt after one minute`() {
        val geofence = inputs(reason = Reason.GEOFENCE, lastFailed = true, since = 2 * 60_000)
        assertEquals(Decision.START, TrackingRecovery.decide(geofence))
    }

    @Test fun `alive marker - only a recent heartbeat counts as healthy`() {
        assertTrue(TrackingRecovery.isAliveMarkerFresh(0))
        assertTrue(TrackingRecovery.isAliveMarkerFresh(60_000))
        assertFalse(TrackingRecovery.isAliveMarkerFresh(TrackingRecovery.ALIVE_MAX_AGE_MS + 1))
        assertFalse(TrackingRecovery.isAliveMarkerFresh(null))
        assertFalse(TrackingRecovery.isAliveMarkerFresh(-5))
    }
}
