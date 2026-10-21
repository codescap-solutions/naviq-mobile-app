package com.truenyx.naviqandroid

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure rules for the bounded high-accuracy burst the native fallback takes
 * when the child is close to a saved place and the high-accuracy foreground
 * service is not running. No Android classes here, so it is JVM unit-tested.
 *
 * The server stays the only judge of ENTRY/EXIT: it will not accept a fix worse
 * than ~40–75 m or older than ~90 s. This policy only decides WHEN it is worth
 * spending a few seconds of GPS to try to produce such a fix, and which fixes
 * are good enough to send — it never relaxes those server requirements.
 */
object NearFencePolicy {
    /** Burst while within this distance OUTSIDE a fence boundary… */
    const val NEAR_OUTSIDE_M = 300.0

    /**
     * …or this far INSIDE it (leaving). Deeper than this, nothing to learn — and a
     * child sitting at home must not trigger a burst every cooldown.
     */
    const val NEAR_INSIDE_M = 60.0

    /** A ping fix worse than this cannot place the child relative to a fence. */
    const val MAX_TRIGGER_ACCURACY_M = 1000.0

    const val BURST_DURATION_MS = 2 * 60 * 1000L
    const val BURST_INTERVAL_MS = 10_000L
    const val BURST_MIN_INTERVAL_MS = 5_000L
    const val BURST_MAX_UPDATES = 8

    /** After a burst, wait this long (from its start) before another one. */
    const val COOLDOWN_MS = 10 * 60 * 1000L

    /** A burst fix is only sent if it is this fresh and this precise. */
    const val MAX_FIX_AGE_MS = 20_000L
    const val MAX_FIX_ACCURACY_M = 75.0

    data class Fence(val lat: Double, val lng: Double, val radiusM: Double)

    fun distanceM(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val r = 6_371_000.0
        val p1 = Math.toRadians(lat1)
        val p2 = Math.toRadians(lat2)
        val dp = p2 - p1
        val dl = Math.toRadians(lng2 - lng1)
        val a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /**
     * Signed distance from the nearest fence BOUNDARY (negative = inside), or
     * null when there are no fences.
     */
    fun nearestEdgeM(lat: Double, lng: Double, fences: List<Fence>): Double? =
        fences.minOfOrNull { distanceM(lat, lng, it.lat, it.lng) - it.radiusM }

    /**
     * Is the child close enough to a boundary — allowing for the ping fix's own
     * uncertainty — to be worth a precise burst? Reliable proximity can't be
     * established from a missing/very coarse fix, so then the answer is no.
     */
    fun isNearBoundary(lat: Double, lng: Double, accuracyM: Double?, fences: List<Fence>): Boolean {
        if (accuracyM == null || accuracyM <= 0.0 || accuracyM > MAX_TRIGGER_ACCURACY_M) return false
        val edge = nearestEdgeM(lat, lng, fences) ?: return false
        val slack = min(accuracyM, 200.0)
        // Outside: allow for the ping fix's own uncertainty. Inside: no slack, so a
        // small fence's centre is never "near the boundary".
        return edge - slack <= NEAR_OUTSIDE_M && edge >= -NEAR_INSIDE_M
    }

    data class BurstInputs(
        val highAccuracyActive: Boolean,
        val nearBoundary: Boolean,
        val nowMs: Long,
        val activeUntilMs: Long,
        val lastBurstStartMs: Long,
    )

    fun shouldStartBurst(i: BurstInputs): Boolean {
        if (i.highAccuracyActive) return false          // the foreground service already produces precise fixes
        if (!i.nearBoundary) return false
        if (i.nowMs < i.activeUntilMs) return false     // already bursting — no duplicate stream
        if (i.lastBurstStartMs > 0 && i.nowMs - i.lastBurstStartMs < COOLDOWN_MS) return false
        return true
    }

    /** A running burst is dropped as soon as the real foreground service is alive (no duplicate streams). */
    fun shouldCancelSuperseded(activeUntilMs: Long, nowMs: Long, highAccuracyActive: Boolean): Boolean =
        activeUntilMs > nowMs && highAccuracyActive

    /**
     * Only a fresh, precise fix may be sent as burst evidence — never a cached
     * one. `ageMs` is measured on the elapsed-realtime clock (immune to wall
     * clock changes).
     */
    fun isUsableBurstFix(ageMs: Long, accuracyM: Double?): Boolean =
        ageMs in 0..MAX_FIX_AGE_MS && accuracyM != null && accuracyM > 0.0 && accuracyM <= MAX_FIX_ACCURACY_M
}
