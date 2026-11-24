package app.gamenative.ui.screen.wow

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MobileProfileCheckpointTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun keepsAndRecoversTheCharacterProfileBesideTheGame() {
        val game = folder.newFolder("game")
        val current = File(game, "_forever_/WTF/Account/Account1/Realm/Player/SavedVariables/ForeverTouch.lua")
        current.parentFile!!.mkdirs()
        val original = "ForeverTouchPreferences = { revision = 5, mobileSlots = { left = {} } }\n"
        current.writeText(original)
        checkpointMobileProfiles(game)
        assertEquals(original, current.readText())

        val newer = original.replace("revision = 5", "revision = 6")
        current.writeText(newer)
        checkpointMobileProfiles(game)
        current.delete()
        checkpointMobileProfiles(game)
        assertEquals(newer, current.readText())
    }

    @Test fun recoversOnlyTheMobileAddonFromTheGameBackup() {
        val game = folder.newFolder("game")
        val variables = File(game, "_forever_/WTF/Account/Account1/SavedVariables").apply { mkdirs() }
        val saved = "ForeverTouchProfiles = { knownProfile = { revision = 5 } }\n"
        File(variables, "ForeverTouch.lua.bak").writeText(saved)
        File(variables, "AnotherAddon.lua.bak").writeText(saved)
        File(variables, "ForeverTouch.lua").writeText("")
        checkpointMobileProfiles(game)
        assertEquals(saved, File(variables, "ForeverTouch.lua").readText())
        assertFalse(File(variables, "AnotherAddon.lua").exists())
    }
}
