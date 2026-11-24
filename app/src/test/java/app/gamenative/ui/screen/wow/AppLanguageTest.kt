package app.gamenative.ui.screen.wow

import android.app.Application
import app.gamenative.R
import app.gamenative.utils.LocaleHelper
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "de")
class AppLanguageTest {
    @get:Rule val files = TemporaryFolder()

    @Test
    fun firstRunRequiresAnExplicitSupportedLanguage() {
        assertNull(AppLanguage.fromTag(""))
        assertNull(AppLanguage.fromTag("es"))
        assertEquals(AppLanguage.GERMAN, AppLanguage.fromTag("de"))
        assertEquals(AppLanguage.ENGLISH, AppLanguage.fromTag("en"))
    }

    @Test
    fun languageOverridesTheDeviceAndRefreshesBothAddonManifests() {
        val application = RuntimeEnvironment.getApplication()
        val root = files.newFolder("wow")
        val addon = root.resolve("${WowClientDownloader.FLAVOR_DIR}/Interface/AddOns/ForeverTouch")
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.GERMANY)
            for ((language, label) in listOf(AppLanguage.GERMAN to "App-Sprache", AppLanguage.ENGLISH to "App language")) {
                val context = LocaleHelper.applyLanguage(application, language.tag)
                assertEquals(label, context.getString(R.string.mobile_app_language))
                assertEquals("eu", WowClientDownloader.defaultBranch())
                installMobileAddon(context, root)
                val toc = addon.resolve("ForeverTouch.toc").readText()
                assertTrue(toc.startsWith("## X-ForeverTouch-Language: ${language.tag}\n"))
                assertEquals(toc, addon.resolve("ForeverTouch_Camelot.toc").readText())
                assertTrue("## SavedVariablesPerCharacter: ForeverTouchPreferences" in toc)
                assertTrue("## X-ForeverTouch-Keyboard: native" in toc)
                assertTrue("ForeverTouchChatHistory.lua" in toc && addon.resolve("ForeverTouchChatHistory.lua").isFile)
            }
        } finally {
            Locale.setDefault(previous)
        }
    }
}
