package com.truenyx.naviqandroid

import com.truenyx.naviqandroid.TrackingRecovery.Decision
import com.truenyx.naviqandroid.TrackingRecovery.Reason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Drives the real [TrackingRecovery.run] orchestration against a fake device. */
class TrackingRecoveryRunTest {
    private class FakeEnv(
        override val sdkInt: Int = 34,
        var child: Boolean = true,
        var fine: Boolean = true,
        var background: Boolean = true,
        var running: Boolean = false,
        var now: Long = 10_000_000L,
        var lastAt: Long = 0L,
        var lastFailed: Boolean = false,
        var startThrows: Exception? = null,
    ) : TrackingRecovery.Env {
        var startCalls = 0
        val recorded = mutableListOf<Triple<Boolean, Reason, String>>()
        val logs = mutableListOf<String>()
        override fun hasChildId() = child
        override fun fineLocationGranted() = fine
        override fun backgroundLocationGranted() = background
        override fun serviceRunning() = running
        override fun nowMs() = now
        override fun lastAttemptAtMs() = lastAt
        override fun lastAttemptFailed() = lastFailed
        override fun startService() {
            startCalls++
            startThrows?.let { throw it }
            running = true // the OS started it
        }
        override fun recordAttempt(atMs: Long, failed: Boolean, reason: Reason, result: String) {
            recorded += Triple(failed, reason, result)
            lastAt = atMs
            lastFailed = failed
        }
        override fun log(message: String) { logs += message }
    }

    @Test fun `eligible events start the service exactly once and record the attempt`() {
        for (r in listOf(Reason.BOOT, Reason.PACKAGE_REPLACED, Reason.GEOFENCE, Reason.WATCHDOG)) {
            val env = FakeEnv()
            assertEquals(Decision.START, TrackingRecovery.run(env, r))
            assertEquals(1, env.startCalls)
            assertEquals(Triple(false, r, "requested"), env.recorded.single())
        }
    }

    @Test fun `duplicate start attempts - boot receiver plus plugin, repeated geofence callbacks - start nothing twice`() {
        val env = FakeEnv()
        assertEquals(Decision.START, TrackingRecovery.run(env, Reason.BOOT))
        // service now running → a second trigger is a no-op
        assertEquals(Decision.SKIP_ALREADY_RUNNING, TrackingRecovery.run(env, Reason.GEOFENCE))
        // it dies again inside the 60 s window → still no repeated start
        env.running = false
        env.now += 30_000
        assertEquals(Decision.SKIP_RECENT_ATTEMPT, TrackingRecovery.run(env, Reason.GEOFENCE))
        assertEquals(1, env.startCalls)
        // after the window a genuinely stopped service is restarted
        env.now += 40_000
        assertEquals(Decision.START, TrackingRecovery.run(env, Reason.GEOFENCE))
        assertEquals(2, env.startCalls)
    }

    @Test fun `missing permissions never reach the OS start call`() {
        val noFine = FakeEnv(fine = false)
        assertEquals(Decision.SKIP_NO_LOCATION_PERMISSION, TrackingRecovery.run(noFine, Reason.BOOT))
        val noBg = FakeEnv(sdkInt = 34, background = false)
        assertEquals(Decision.SKIP_NO_BACKGROUND_LOCATION, TrackingRecovery.run(noBg, Reason.PACKAGE_REPLACED))
        val parent = FakeEnv(child = false)
        assertEquals(Decision.SKIP_NOT_CHILD, TrackingRecovery.run(parent, Reason.BOOT))
        assertEquals(0, noFine.startCalls + noBg.startCalls + parent.startCalls)
        assertTrue("a refused-for-permission skip is logged", noFine.logs.isNotEmpty() && noBg.logs.isNotEmpty())
    }

    @Test fun `service-start failure is recorded explicitly, never thrown, and the watchdog backs off`() {
        val env = FakeEnv(startThrows = IllegalStateException("ForegroundServiceStartNotAllowed"))
        assertEquals(Decision.START, TrackingRecovery.run(env, Reason.WATCHDOG)) // must not throw
        assertEquals(Triple(true, Reason.WATCHDOG, "IllegalStateException"), env.recorded.single())
        assertTrue(env.lastFailed)
        // the watchdog does not hammer a device that refuses
        env.now += 5 * 60_000
        assertEquals(Decision.SKIP_RECENT_ATTEMPT, TrackingRecovery.run(env, Reason.WATCHDOG))
        assertEquals(1, env.startCalls)
        // an event Android DOES allow (geofence) may try again after the normal gap
        assertEquals(Decision.START, TrackingRecovery.run(env, Reason.GEOFENCE))
        assertEquals(2, env.startCalls)
    }

    @Test fun `a SecurityException from the OS is also contained`() {
        val env = FakeEnv(startThrows = SecurityException("missing FOREGROUND_SERVICE_LOCATION"))
        TrackingRecovery.run(env, Reason.BOOT)
        assertEquals("SecurityException", env.recorded.single().third)
    }

    @Test fun `recovery only requests a start - it never claims tracking is healthy`() {
        val env = FakeEnv()
        TrackingRecovery.run(env, Reason.BOOT)
        // 'running' came from the OS; the health signal is a separate, fresh Dart heartbeat
        assertFalse(TrackingRecovery.isAliveMarkerFresh(null))
        assertFalse(TrackingRecovery.isAliveMarkerFresh(TrackingRecovery.ALIVE_MAX_AGE_MS + 1))
    }
}
