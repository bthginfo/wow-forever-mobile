package app.gamenative.ui.screen.xserver

import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import app.gamenative.ui.component.InlineKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class MobileFullscreenChatTest {
    @Test fun `the keyboard transport preserves UTF-8 and normalizes pasted line breaks`() {
        val packet = checkNotNull(fullscreenChatMessagePacket(" Grüße\nfür die Gruppe! 😀 "))
        val bytes = packet.drop(4).chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        assertEquals(bytes.size, packet.substring(1, 4).toInt())
        assertEquals(" Grüße für die Gruppe! 😀 ", bytes.decodeToString())
    }

    @Test fun `blank or oversized messages remain unsent`() {
        assertNull(fullscreenChatMessagePacket("\n \t"))
        assertNotNull(fullscreenChatMessagePacket("a".repeat(255)))
        assertNotNull(fullscreenChatMessagePacket("ü".repeat(127)))
        assertNull(fullscreenChatMessagePacket("ü".repeat(128)))
    }

    @Test fun `app keys replace the selection and keep pasted text on one line`() {
        val draft = TextFieldValue("/g alles!", TextRange(8, 3))
        val edited = insertChatText(draft, "Grüße\nzusammen")
        assertEquals("/g Grüße zusammen!", edited.text)
        assertEquals(TextRange(17), edited.selection)
    }

    @Test fun `arrows and backspace treat a supplementary character as one character`() {
        val draft = TextFieldValue("a😀b", TextRange(3))
        assertEquals(TextRange(1), editChatText(draft, InlineKey.LEFT).selection)
        assertEquals(TextRange(4), editChatText(draft, InlineKey.RIGHT).selection)
        val deleted = editChatText(draft, InlineKey.BACKSPACE)
        assertEquals("ab", deleted.text)
        assertEquals(TextRange(1), deleted.selection)
    }
}
