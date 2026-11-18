package app.gamenative.ui.screen.wow.auth

import android.app.Activity
import android.app.Application
import android.content.MutableContextWrapper
import android.os.Looper
import android.webkit.WebView
import android.widget.FrameLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [34])
class BattleNetWebPageTest {
    @Test
    fun keepsTheLivePageDuringAnAppSwitchAndReattachesItToANewDialogHost() {
        val first = Robolectric.buildActivity(Activity::class.java).setup()
        val second = Robolectric.buildActivity(Activity::class.java).setup()
        val page = BattleNetWebPage("https://eu.battle.net/login", {}, { error(it) })
        try {
            val originalHost = FrameLayout(first.get())
            first.get().setContentView(originalHost)
            page.attach(originalHost)
            val browser = originalHost.getChildAt(0) as WebView
            val authenticatorStep = "https://eu.battle.net/authenticator"
            browser.loadUrl(authenticatorStep)

            first.pause().stop()
            assertSame(browser, originalHost.getChildAt(0))
            page.detach(originalHost)
            val browserContext = browser.context as MutableContextWrapper
            assertSame(first.get().applicationContext, browserContext.baseContext)

            val newHost = FrameLayout(second.get())
            second.get().setContentView(newHost)
            page.attach(newHost)

            assertSame(browser, newHost.getChildAt(0))
            assertSame(newHost.context, browserContext.baseContext)
            assertEquals(authenticatorStep, shadowOf(browser).lastLoadedUrl)
            assertEquals(0, originalHost.childCount)
        } finally {
            page.close()
            shadowOf(Looper.getMainLooper()).idle()
            second.pause().stop().destroy()
            first.destroy()
        }
    }

    @Test
    fun closingTheAttemptReleasesThePageAndPreventsReopeningItsChallenge() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup()
        val host = FrameLayout(activity.get())
        val page = BattleNetWebPage("https://eu.battle.net/login", {}, { error(it) })
        page.attach(host)
        val browser = host.getChildAt(0) as WebView
        page.close()
        shadowOf(Looper.getMainLooper()).idle()

        assertTrue(shadowOf(browser).wasDestroyCalled())
        page.attach(host)
        assertEquals(0, host.childCount)
        activity.pause().stop().destroy()
    }
}
