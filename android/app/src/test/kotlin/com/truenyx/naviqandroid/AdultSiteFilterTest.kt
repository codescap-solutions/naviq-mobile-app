package com.truenyx.naviqandroid

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdultSiteFilterTest {

    @Test
    fun blocksListedDomainsAndTheirSubdomains() {
        assertTrue(AdultSiteFilter.isBlocked("pornhub.com"))
        assertTrue(AdultSiteFilter.isBlocked("https://www.xvideos.com/video123"))
        assertTrue(AdultSiteFilter.isBlocked("m.xhamster.com"))
        assertTrue(AdultSiteFilter.isBlocked("fr.pornhub.com/view"))
    }

    @Test
    fun blocksWholeWordKeywords() {
        assertTrue(AdultSiteFilter.isBlocked("sex.com"))
        assertTrue(AdultSiteFilter.isBlocked("free-xxx-videos.net"))
        assertTrue(AdultSiteFilter.isBlocked("google.com/search?q=nsfw"))
    }

    @Test
    fun blocksDistinctiveNamesAnywhereInTheHost() {
        assertTrue(AdultSiteFilter.isBlocked("bestpornsite.org"))
        assertTrue(AdultSiteFilter.isBlocked("hentaihaven.xyz"))
    }

    @Test
    fun doesNotBlockInnocentSitesThatContainTheLetters() {
        assertFalse(AdultSiteFilter.isBlocked("essex.ac.uk"))
        assertFalse(AdultSiteFilter.isBlocked("sussex.ac.uk"))
        assertFalse(AdultSiteFilter.isBlocked("middlesex.edu"))
        assertFalse(AdultSiteFilter.isBlocked("adultswim.com"))
        assertFalse(AdultSiteFilter.isBlocked("adult education classes"))
        assertFalse(AdultSiteFilter.isBlocked("wikipedia.org/wiki/Sextant"))
    }

    @Test
    fun ignoresEmptyText() {
        assertFalse(AdultSiteFilter.isBlocked(""))
        assertFalse(AdultSiteFilter.isBlocked("   "))
    }

    // What browsers actually put in the address bar.

    @Test
    fun ignoresCaseAndPortsAndUserInfo() {
        assertTrue(AdultSiteFilter.isBlocked("PORNHUB.COM"))
        assertTrue(AdultSiteFilter.isBlocked("https://www.pornhub.com:443/view?x=1"))
        assertTrue(AdultSiteFilter.isBlocked("http://user@pornhub.com"))
        assertTrue(AdultSiteFilter.isBlocked("https://pornhub.com#top"))
    }

    @Test
    fun blocksAdultSearchesTypedIntoTheBar() {
        assertTrue(AdultSiteFilter.isBlocked("porn videos"))
        assertTrue(AdultSiteFilter.isBlocked("google.com/search?q=free+porn"))
        assertTrue(AdultSiteFilter.isBlocked("nsfw reddit"))
    }

    @Test
    fun allowsNormalBrowsing() {
        assertFalse(AdultSiteFilter.isBlocked("google.com"))
        assertFalse(AdultSiteFilter.isBlocked("https://www.youtube.com/watch?v=abc"))
        assertFalse(AdultSiteFilter.isBlocked("en.wikipedia.org/wiki/Sussex"))
        assertFalse(AdultSiteFilter.isBlocked("bbc.co.uk/news"))
        assertFalse(AdultSiteFilter.isBlocked("how to learn kotlin"))
        assertFalse(AdultSiteFilter.isBlocked("amazon.in/dp/B0123"))
    }

    @Test
    fun aListedDomainOnlyMatchesAsARealSuffix() {
        // "notpornhub.com" still trips the "porn" keyword rule on purpose; a
        // look-alike that merely ends with a listed name must not skip it.
        assertTrue(AdultSiteFilter.isBlocked("notpornhub.com"))
        assertTrue(AdultSiteFilter.isBlocked("pornhub.com.evil.example"))
    }
}
