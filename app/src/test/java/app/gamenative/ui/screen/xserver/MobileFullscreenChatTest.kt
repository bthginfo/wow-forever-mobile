package app.gamenative.ui.screen.xserver

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
}
