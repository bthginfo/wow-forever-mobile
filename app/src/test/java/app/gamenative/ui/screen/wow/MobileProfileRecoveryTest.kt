package app.gamenative.ui.screen.wow

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MobileProfileRecoveryTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun recoversProfilesEvenWhenWoWReplacesThemWithDefaults() {
        val game = folder.newFolder("game")
        val account = File(game, "_forever_/WTF/Account/Account1/SavedVariables/ForeverTouch.lua")
        val old = File(account.path + ".bak")
        account.parentFile!!.mkdirs()
        account.writeText("ForeverTouchProfiles = { ['Player-70-AB'] = { revision = 15, mobileChatOpen = true } }")
        old.writeText(
            """
            ForeverTouchProfiles = {
                ["Player-70-AB"] = { revision = 14, arcRevision = 14, mobileArcPage = 2,
                    mobileArcPages = { { slots = { left = { { kind = "item", id = 501 } }, right = {} } } },
                    mobileArcPositions = { left = { x = .18, y = 4.2e-1 } } },
                ["Player-70-CD"] = { revision = 3, mobileArcPage = 3 },
            }
            ForeverTouchFrameLimit = nil
            """.trimIndent(),
        )

        val first = recoverMobileProfiles(game)
        account.writeText("ForeverTouchProfiles = {}")
        old.writeText("ForeverTouchProfiles = {}")
        val restart = recoverMobileProfiles(game)
        assertEquals(first.decodeToString(), restart.decodeToString())
        val profiles = restored(restart)["profiles"] as LuaTable
        val arc = profiles["Player-70-AB"] as LuaTable
        assertEquals(15L, arc["revision"])
        assertEquals(14L, arc["arcRevision"])
        assertEquals(2L, arc["mobileArcPage"])
        assertEquals(true, arc["mobileChatOpen"])
        assertTrue(arc.containsKey("mobileArcPages"))
        assertTrue(profiles.containsKey("Player-70-CD"))

        // An explicit newer reset must beat any older arc data in the backup.
        account.writeText("ForeverTouchProfiles = { ['Player-70-AB'] = { revision = 16, arcRevision = 16 } }")
        val afterReset = restored(recoverMobileProfiles(game))["profiles"] as LuaTable
        assertFalse((afterReset["Player-70-AB"] as LuaTable).containsKey("mobileArcPages"))
        assertTrue(afterReset.containsKey("Player-70-CD"))
    }

    @Test fun readsNumericRealmDirectoriesAndRejectsExecutableLua() {
        val game = folder.newFolder("game")
        val player = File(game, "_forever_/WTF/Account/Account1/70/Händler-My Realm/SavedVariables")
        player.mkdirs()
        File(player, "ForeverTouch.lua").writeText("ForeverTouchPreferences = { revision = 12, mobileArcPage = 2 }")
        File(player, "ForeverTouch.lua.bak").writeText("ForeverTouchPreferences = { revision = 50, value = print('run') }")
        val unrelated = File(game, "_forever_/WTF/Account/Account1/SavedVariables/Unrelated.lua")
        unrelated.parentFile!!.mkdirs()
        unrelated.writeText("ForeverTouchProfiles = { ['Player-70-Unrelated'] = { revision = 50 } }")
        val recovered = restored(recoverMobileProfiles(game))
        val profiles = recovered["characters"] as LuaTable
        assertEquals(setOf("70/händler-myrealm"), profiles.keys)
        assertEquals(12L, (profiles["70/händler-myrealm"] as LuaTable)["revision"])
        assertTrue((recovered["profiles"] as LuaTable).isEmpty())
    }

    private fun restored(data: ByteArray): LuaTable =
        parseLuaData("data = " + data.decodeToString().substringAfter("addon.recoveredProfiles = "))["data"] as LuaTable
}
