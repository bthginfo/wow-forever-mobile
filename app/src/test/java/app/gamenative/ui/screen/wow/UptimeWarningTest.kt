package app.gamenative.ui.screen.wow

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UptimeWarningTest {
    private val day = 86_400_000L

    @Test
    fun noRebootHintBeforeTheTimerCanWrap() {
        assertFalse(mightHaveWrappedLoginTimer(0))
        assertFalse(mightHaveWrappedLoginTimer(49 * day))
        assertFalse(mightHaveWrappedLoginTimer(4_294_967_295L))
    }

    @Test
    fun detectsUptimeAtOrBeyondTheTimerLimit() {
        assertTrue(mightHaveWrappedLoginTimer(4_294_967_296L))
        assertTrue(mightHaveWrappedLoginTimer(58 * day))
    }
}
