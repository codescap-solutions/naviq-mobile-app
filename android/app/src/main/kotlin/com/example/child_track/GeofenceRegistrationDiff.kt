package com.truenyx.naviqandroid

/**
 * Which fences actually changed since the last successful registration?
 *
 * Re-adding a fence with INITIAL_TRIGGER_ENTER makes Play Services report ENTER
 * immediately when the device is already inside — so re-registering an
 * UNCHANGED fence on every periodic sync (Dart ~10 min, watchdog 15 min)
 * produced a fresh ENTER hint each time (duplicate arrival timeline events, a
 * reset "here since" timer). Only new or edited fences keep the initial ENTER
 * (a child already inside a just-created place should be noticed); unchanged
 * fences are re-armed with no initial trigger.
 */
object GeofenceRegistrationDiff {
    data class Fence(val id: String, val lat: Double, val lng: Double, val radiusM: Double)

    data class Plan(val newOrChanged: List<Fence>, val unchanged: List<Fence>)

    /** == GeofencingRequest.INITIAL_TRIGGER_ENTER (1) / "no initial trigger" (0). */
    const val INITIAL_ENTER = 1
    const val INITIAL_NONE = 0

    data class Group(val fences: List<Fence>, val initialTrigger: Int)

    /**
     * The registration requests to make: NEW/EDITED fences keep the initial ENTER
     * (a child already inside a just-created place should be noticed); UNCHANGED
     * ones are re-armed with no initial trigger. Empty groups are omitted.
     */
    fun groups(plan: Plan): List<Group> = listOfNotNull(
        plan.newOrChanged.takeIf { it.isNotEmpty() }?.let { Group(it, INITIAL_ENTER) },
        plan.unchanged.takeIf { it.isNotEmpty() }?.let { Group(it, INITIAL_NONE) },
    )

    fun signature(f: Fence): String = "%.6f|%.6f|%.1f".format(java.util.Locale.US, f.lat, f.lng, f.radiusM)

    /** @param previous id → signature of what was successfully registered last time. */
    fun plan(previous: Map<String, String>, current: List<Fence>): Plan {
        val (same, diff) = current.partition { previous[it.id] == signature(it) }
        return Plan(newOrChanged = diff, unchanged = same)
    }
}
