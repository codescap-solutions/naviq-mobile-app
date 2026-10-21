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
}
