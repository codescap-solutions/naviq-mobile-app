package com.truenyx.naviqandroid

import java.util.Locale

/**
 * Decides whether the text in a browser's address bar is an adult site.
 *
 * The old check blocked any URL that merely contained "sex" / "adult", which
 * also blocked essex.ac.uk, sussex, middlesex... This one matches on whole
 * words and on domains instead. It is a blocklist, so it can never be
 * complete; it just has to be right about what it names.
 */
object AdultSiteFilter {

    /** Well-known adult domains (same list as the iOS filter). */
    private val BLOCKED_DOMAINS = setOf(
        "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com",
        "youporn.com", "tube8.com", "spankbang.com", "xxx.com", "porn.com",
        "brazzers.com", "onlyfans.com", "chaturbate.com", "livejasmin.com",
        "myfreecams.com", "camsoda.com", "stripchat.com", "bongacams.com",
        "tnaflix.com", "motherless.com", "rule34.xxx", "e-hentai.org",
        "nhentai.net", "thumbzilla.com", "beeg.com", "txxx.com", "hclips.com",
        "drtuber.com", "sunporno.com", "porntrex.com", "eporner.com",
        "xtube.com", "adultfriendfinder.com", "ashleymadison.com",
        "literotica.com", "hqporner.com", "pornone.com", "3movs.com",
        "javhd.com", "fapdu.com", "keezmovies.com", "extremetube.com",
        "4tube.com", "vporn.com", "camwhores.tv", "fetlife.com",
    )

    /** Long, distinctive names: blocked when they appear anywhere in the host. */
    private val BLOCKED_SUBSTRINGS = setOf(
        "porn", "xvideo", "xhamster", "redtube", "brazzers", "youporn", "xnxx",
        "chaturbate", "livejasmin", "hentai",
    )

    /** Short or ambiguous words: blocked only as a whole word ("sex.com"). */
    private val BLOCKED_WORDS = setOf("sex", "xxx", "nsfw")

    fun isBlocked(addressBarText: String): Boolean {
        val text = addressBarText.trim().lowercase(Locale.ROOT)
        if (text.isEmpty()) return false

        val host = hostOf(text)
        if (BLOCKED_DOMAINS.any { host == it || host.endsWith(".$it") }) return true
        if (BLOCKED_SUBSTRINGS.any { host.contains(it) }) return true

        val words = text.split(NON_ALPHANUMERIC).filter { it.isNotEmpty() }
        return words.any { it in BLOCKED_WORDS || BLOCKED_SUBSTRINGS.any { s -> it.contains(s) } }
    }

    private val NON_ALPHANUMERIC = Regex("[^a-z0-9]+")

    private fun hostOf(text: String): String {
        val noScheme = text.substringAfter("://")
        val host = noScheme.takeWhile { it != '/' && it != '?' && it != '#' && it != ':' }
        return host.removePrefix("www.").removePrefix("m.")
    }
}
