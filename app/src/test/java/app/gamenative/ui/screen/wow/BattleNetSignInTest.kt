package app.gamenative.ui.screen.wow

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BattleNetSignInTest {
    @Test
    fun savedLoginRejectsCharactersThatSplitTheGameLoginFile() {
        assertTrue(BattleNetSignIn.Login("player@example.com", "p ä ss").canWriteLoginFile)
        assertFalse(BattleNetSignIn.Login("player@example.com\nother", "secret").canWriteLoginFile)
        assertFalse(BattleNetSignIn.Login("player@example.com", "secret\r").canWriteLoginFile)
        assertFalse(BattleNetSignIn.Login("player@example.com", "secret\u0000").canWriteLoginFile)
    }
}
