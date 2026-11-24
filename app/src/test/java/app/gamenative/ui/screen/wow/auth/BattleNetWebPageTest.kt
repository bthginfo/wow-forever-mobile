package app.gamenative.ui.screen.wow.auth

import android.app.Activity
import android.app.Application
import android.content.MutableContextWrapper
import android.content.Context
import android.os.Looper
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
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
    fun typesOnlyIntoTheActiveAllowedWebEditor() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup()
        val editor = TestEditor(activity.get())
        try {
            dispatchBattleNetInlineInput(editor, { true }) { commitText("ü7@", 1) }
            assertEquals(listOf("ü7@"), editor.received)

            editor.editorFocused = false
            dispatchBattleNetInlineInput(editor, { true }) { commitText("no editor", 1) }
            editor.editorFocused = true
            editor.address = "https://example.test/form"
            dispatchBattleNetInlineInput(editor, { true }) { commitText("wrong origin", 1) }
            editor.address = "https://eu.battle.net/login"
            dispatchBattleNetInlineInput(editor, { false }) { commitText("expired session", 1) }
            assertEquals(listOf("ü7@"), editor.received)
        } finally {
            editor.destroy()
            activity.pause().stop().destroy()
        }
    }

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

    private class TestEditor(context: Context) : WebView(context) {
        var address = "https://eu.battle.net/login"
        var editorFocused = true
        val received = mutableListOf<String>()

        override fun isAttachedToWindow() = true
        override fun hasWindowFocus() = true
        override fun hasFocus() = true
        override fun onCheckIsTextEditor() = editorFocused
        override fun getUrl() = address
        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection = object : BaseInputConnection(this, true) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                received += text.toString()
                return true
            }
        }
    }
}
