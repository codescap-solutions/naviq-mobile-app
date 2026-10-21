package com.truenyx.naviqandroid

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeDeviceTimeTest {
    @Test fun `location and geofence-event posts carry the send-time stamp`() {
        assertTrue(NativeApiClient.carriesDeviceTime("child/location"))
        assertTrue(NativeApiClient.carriesDeviceTime("child/geofence-event"))
    }

    @Test fun `other posts are left untouched`() {
        assertFalse(NativeApiClient.carriesDeviceTime("child/device-status"))
        assertFalse(NativeApiClient.carriesDeviceTime("trip-tracking/c1/locations"))
        assertFalse(NativeApiClient.carriesDeviceTime(""))
    }

    @Test fun `the stamp is an ISO-8601 UTC millisecond string, distinct from any capture time`() {
        assertTrue(NativeApiClient.deviceTimeIso(1_700_000_000_000L) == "2023-11-14T22:13:20.000Z")
    }
}
