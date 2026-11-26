package app.gamenative.ui.screen.xserver

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GameFrameRateTest {
    @Test
    fun hiddenGamesDropToTheBackgroundCapUnlessThePlayerChoseLess() {
        assertEquals(BACKGROUND_FRAME_LIMIT, backgroundFrameLimit(60))
        assertEquals(BACKGROUND_FRAME_LIMIT, backgroundFrameLimit(0))
        assertEquals(5, backgroundFrameLimit(5))
    }

    @Test
    fun aSixtyFpsCapPrefersSixtyHertzOnAOneTwentyHertzPanel() {
        assertEquals(60f, preferredRefreshRate(60, listOf(120f, 60f, 90f)))
        assertEquals(59.94f, preferredRefreshRate(60, listOf(59.94f, 120f)))
    }

    @Test
    fun lowCapsKeepTheOverlayAtSixtyHertzAndOddCapsUseAnEvenMultiple() {
        assertEquals(60f, preferredRefreshRate(30, listOf(30f, 60f, 120f)))
        assertEquals(90f, preferredRefreshRate(45, listOf(60f, 90f, 120f)))
        assertEquals(120f, preferredRefreshRate(40, listOf(60f, 120f)))
    }

    @Test
    fun withoutACapOrAMatchingModeTheSystemKeepsChoosing() {
        assertNull(preferredRefreshRate(0, listOf(60f, 120f)))
        assertNull(preferredRefreshRate(144, listOf(60f, 120f)))
        assertEquals(120f, preferredRefreshRate(100, listOf(60f, 120f)))
    }
}
