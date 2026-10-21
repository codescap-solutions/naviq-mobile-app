package com.truenyx.naviqandroid

import com.google.android.gms.location.GeofencingRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Source-level checks of the manifest wiring (no device needed) plus the geofence
 * registration grouping. The MERGED manifest is checked separately by the build
 * (see the report): this proves the source declares what we rely on.
 */
class ManifestAndRegistrationTest {
    private val ANDROID = "http://schemas.android.com/apk/res/android"
    private val TOOLS = "http://schemas.android.com/tools"
    private val PLUGIN_BOOT = "id.flutter.flutter_background_service.BootReceiver"

    private val manifest by lazy {
        val f = listOf(File("src/main/AndroidManifest.xml"), File("app/src/main/AndroidManifest.xml")).first { it.exists() }
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        factory.newDocumentBuilder().parse(f).documentElement
    }

    private fun receivers() = manifest.getElementsByTagName("receiver").let { n -> (0 until n.length).map { n.item(it) as org.w3c.dom.Element } }

    @Test fun `the plugin's unguarded boot receiver is removed from the merged manifest`() {
        val removal = receivers().single { it.getAttributeNS(ANDROID, "name") == PLUGIN_BOOT }
        assertEquals("remove", removal.getAttributeNS(TOOLS, "node"))
    }

    @Test fun `our guarded BootReceiver covers boot, quick-boot and app update`() {
        val ours = receivers().single { it.getAttributeNS(ANDROID, "name") == ".BootReceiver" }
        val actions = ours.getElementsByTagName("action").let { n -> (0 until n.length).map { (n.item(it) as org.w3c.dom.Element).getAttributeNS(ANDROID, "name") } }
        assertTrue(actions.containsAll(listOf(
            "android.intent.action.BOOT_COMPLETED",
            "android.intent.action.QUICKBOOT_POWERON",
            "android.intent.action.MY_PACKAGE_REPLACED",
        )))
    }

    @Test fun `the location foreground service keeps its location type and permissions`() {
        val services = manifest.getElementsByTagName("service").let { n -> (0 until n.length).map { n.item(it) as org.w3c.dom.Element } }
        val bg = services.single { it.getAttributeNS(ANDROID, "name") == "id.flutter.flutter_background_service.BackgroundService" }
        assertEquals("location", bg.getAttributeNS(ANDROID, "foregroundServiceType"))
        val perms = manifest.getElementsByTagName("uses-permission").let { n -> (0 until n.length).map { (n.item(it) as org.w3c.dom.Element).getAttributeNS(ANDROID, "name") } }
        assertTrue(perms.containsAll(listOf(
            "android.permission.FOREGROUND_SERVICE",
            "android.permission.FOREGROUND_SERVICE_LOCATION",
            "android.permission.ACCESS_BACKGROUND_LOCATION",
            "android.permission.RECEIVE_BOOT_COMPLETED",
        )))
        assertNotNull(receivers().singleOrNull { it.getAttributeNS(ANDROID, "name") == ".LocationPingBroadcastReceiver" })
    }

    // ── geofence registration ────────────────────────────────────────────────
    private val home = GeofenceRegistrationDiff.Fence("home", 11.25, 75.78, 100.0)
    private val school = GeofenceRegistrationDiff.Fence("school", 11.30, 75.80, 150.0)

    @Test fun `trigger constants match Play Services`() {
        assertEquals(GeofencingRequest.INITIAL_TRIGGER_ENTER, GeofenceRegistrationDiff.INITIAL_ENTER)
        assertEquals(0, GeofenceRegistrationDiff.INITIAL_NONE)
    }

    @Test fun `first sync - one group with the initial ENTER, so a first entry is not lost`() {
        val g = GeofenceRegistrationDiff.groups(GeofenceRegistrationDiff.plan(emptyMap(), listOf(home, school)))
        assertEquals(1, g.size)
        assertEquals(GeofenceRegistrationDiff.INITIAL_ENTER, g[0].initialTrigger)
        assertEquals(listOf(home, school), g[0].fences)
    }

    @Test fun `periodic re-sync of unchanged fences - one group with NO initial trigger (no fabricated ENTER hint)`() {
        val prev = mapOf("home" to GeofenceRegistrationDiff.signature(home), "school" to GeofenceRegistrationDiff.signature(school))
        val g = GeofenceRegistrationDiff.groups(GeofenceRegistrationDiff.plan(prev, listOf(home, school)))
        assertEquals(1, g.size)
        assertEquals(GeofenceRegistrationDiff.INITIAL_NONE, g[0].initialTrigger)
    }

    @Test fun `new place added later - the new one gets ENTER, the existing one stays silent`() {
        val prev = mapOf("home" to GeofenceRegistrationDiff.signature(home))
        val g = GeofenceRegistrationDiff.groups(GeofenceRegistrationDiff.plan(prev, listOf(home, school)))
        assertEquals(listOf(GeofenceRegistrationDiff.INITIAL_ENTER to listOf(school), GeofenceRegistrationDiff.INITIAL_NONE to listOf(home)), g.map { it.initialTrigger to it.fences })
    }

    @Test fun `no fences - no requests`() {
        assertEquals(emptyList<GeofenceRegistrationDiff.Group>(), GeofenceRegistrationDiff.groups(GeofenceRegistrationDiff.plan(emptyMap(), emptyList())))
    }

    @Test fun `device_time is an ISO-8601 UTC millisecond stamp`() {
        assertTrue(Regex("""\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z""").matches(NativeApiClient.deviceTimeIso(1_791_600_000_000L)))
        assertEquals("1970-01-01T00:00:00.000Z", NativeApiClient.deviceTimeIso(0L))
    }
}
