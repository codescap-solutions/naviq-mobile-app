package com.truenyx.naviqandroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Drives the real [NearFenceBurst.decideAndStart] orchestration against a fake device. */
class NearFenceBurstTest {
    private val home = NearFencePolicy.Fence(11.2500, 75.7800, 100.0)
    private fun north(metres: Double) = 11.2500 + metres / 111_195.0

    private class FakeEnv(
        val fences: List<NearFencePolicy.Fence>,
        var active: Boolean = false,
        var now: Long = 50_000_000L,
        var activeUntil: Long = 0L,
        var lastStart: Long = 0L,
        var canRequest: Boolean = true,
    ) : NearFenceBurst.Env {
        var requests = 0
        val logs = mutableListOf<String>()
        override fun fences() = fences
        override fun highAccuracyActive() = active
        override fun nowMs() = now
        override fun activeUntilMs() = activeUntil
        override fun lastStartMs() = lastStart
        override fun requestBurst(): Boolean { requests++; return canRequest }
        override fun recordStart(nowMs: Long) { lastStart = nowMs; activeUntil = nowMs + NearFencePolicy.BURST_DURATION_MS }
        override fun log(message: String) { logs += message }
    }

    @Test fun `near-fence activation with only the fallback running registers one bounded burst`() {
        val env = FakeEnv(listOf(home))
        assertTrue(NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0))
        assertEquals(1, env.requests)
        assertEquals(env.now + NearFencePolicy.BURST_DURATION_MS, env.activeUntil)
    }

    @Test fun `duplicate triggers while a burst is active register nothing more`() {
        val env = FakeEnv(listOf(home))
        assertTrue(NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0))
        env.now += 20_000
        assertFalse(NearFenceBurst.decideAndStart(env, north(240.0), home.lng, 50.0))
        assertEquals(1, env.requests)
    }

    @Test fun `burst expiry, then cooldown, then it may start again`() {
        val env = FakeEnv(listOf(home))
        NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0)
        env.now += NearFencePolicy.BURST_DURATION_MS + 1_000      // burst expired…
        assertFalse("…but still cooling down", NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0))
        env.now += NearFencePolicy.COOLDOWN_MS                     // cooldown over
        assertTrue(NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0))
        assertEquals(2, env.requests)
    }

    @Test fun `no burst while the real foreground service is alive (no duplicate stream)`() {
        val env = FakeEnv(listOf(home), active = true)
        assertFalse(NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0))
        assertEquals(0, env.requests)
    }

    @Test fun `far from every fence, or with no fences, the lightweight fallback is left alone`() {
        assertFalse(NearFenceBurst.decideAndStart(FakeEnv(listOf(home)), north(3_000.0), home.lng, 50.0))
        assertFalse(NearFenceBurst.decideAndStart(FakeEnv(emptyList()), north(250.0), home.lng, 50.0))
    }

    @Test fun `no reliable proximity (missing or very coarse ping fix) - no burst and no invented distance`() {
        assertFalse(NearFenceBurst.decideAndStart(FakeEnv(listOf(home)), north(250.0), home.lng, null))
        assertFalse(NearFenceBurst.decideAndStart(FakeEnv(listOf(home)), north(250.0), home.lng, 5_000.0))
    }

    @Test fun `a refused registration (e g missing permission) leaves no active burst or cooldown behind`() {
        val env = FakeEnv(listOf(home), canRequest = false)
        assertFalse(NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0))
        assertEquals(0L, env.activeUntil)
        assertEquals(0L, env.lastStart)
        // so a later attempt with permission is not blocked by a cooldown that never started
        env.canRequest = true
        assertTrue(NearFenceBurst.decideAndStart(env, north(250.0), home.lng, 50.0))
    }

    @Test fun `cancellation - a running burst is dropped when the service comes alive, not otherwise`() {
        val now = 1_000L
        assertTrue(NearFencePolicy.shouldCancelSuperseded(activeUntilMs = now + 60_000, nowMs = now, highAccuracyActive = true))
        assertFalse("service not alive", NearFencePolicy.shouldCancelSuperseded(now + 60_000, now, false))
        assertFalse("burst already over", NearFencePolicy.shouldCancelSuperseded(now - 1, now, true))
    }
}
