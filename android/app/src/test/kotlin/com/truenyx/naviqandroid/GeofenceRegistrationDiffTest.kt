package com.truenyx.naviqandroid

import com.truenyx.naviqandroid.GeofenceRegistrationDiff.Fence
import org.junit.Assert.assertEquals
import org.junit.Test

class GeofenceRegistrationDiffTest {
    private val home = Fence("home", 11.25, 75.78, 100.0)
    private val school = Fence("school", 11.30, 75.80, 150.0)

    @Test fun `first registration - everything is new and keeps the initial ENTER (first entry is not lost)`() {
        val plan = GeofenceRegistrationDiff.plan(emptyMap(), listOf(home, school))
        assertEquals(listOf(home, school), plan.newOrChanged)
        assertEquals(emptyList<Fence>(), plan.unchanged)
    }

    @Test fun `periodic re-sync of identical fences produces no initial-trigger group`() {
        val prev = mapOf("home" to GeofenceRegistrationDiff.signature(home), "school" to GeofenceRegistrationDiff.signature(school))
        val plan = GeofenceRegistrationDiff.plan(prev, listOf(school, home))
        assertEquals(emptyList<Fence>(), plan.newOrChanged)
        assertEquals(2, plan.unchanged.size)
    }

    @Test fun `an edited radius or moved centre counts as changed`() {
        val prev = mapOf("home" to GeofenceRegistrationDiff.signature(home))
        assertEquals(listOf(home.copy(radiusM = 200.0)), GeofenceRegistrationDiff.plan(prev, listOf(home.copy(radiusM = 200.0))).newOrChanged)
        assertEquals(listOf(home.copy(lat = 11.26)), GeofenceRegistrationDiff.plan(prev, listOf(home.copy(lat = 11.26))).newOrChanged)
    }

    @Test fun `a newly added place is new while the existing one stays unchanged`() {
        val prev = mapOf("home" to GeofenceRegistrationDiff.signature(home))
        val plan = GeofenceRegistrationDiff.plan(prev, listOf(home, school))
        assertEquals(listOf(school), plan.newOrChanged)
        assertEquals(listOf(home), plan.unchanged)
    }

    @Test fun `float noise below the stored precision does not look like an edit`() {
        val prev = mapOf("home" to GeofenceRegistrationDiff.signature(home))
        val plan = GeofenceRegistrationDiff.plan(prev, listOf(home.copy(lat = 11.25 + 1e-9)))
        assertEquals(emptyList<Fence>(), plan.newOrChanged)
    }

    @Test fun `a fence that failed to register last time is retried as new`() {
        val plan = GeofenceRegistrationDiff.plan(mapOf("school" to GeofenceRegistrationDiff.signature(school)), listOf(home, school))
        assertEquals(listOf(home), plan.newOrChanged)
    }
}
