package app.gamenative.ui.screen.wow

import java.io.File
import java.nio.ByteBuffer
import java.util.zip.Adler32
import java.util.zip.Deflater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MobileArcTransferTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun savesWithoutAnyWowSavedVariablesAndRestoresAfterRestart() {
        val root = folder.newFolder("game")
        val data = """Arc={key="Player-22-ABC",nameKey="character:3/realm/händler",profile={revision=12,
            arcRevision=11,mobileChatOpen=true,mobileArcPage=2,mobileSlots={left={},right={{kind="spell",id=120}}},
            mobileArcPositions={right={x=.81,y=.54}},mobileArcPages={{slots={left={{kind="item",id=501}},right={}}}}}}"""
        val compressed = deflate(data.toByteArray())
        val frame = frame(compressed, serial = 876, encoding = 1)
        val save = checkNotNull(MobileArcTransfer(SESSION).readFrame { frame[it] })
        assertEquals(data, save.data)
        saveMobileArcProfile(root, save.data)

        // The WoW process has died, and never wrote a SavedVariables file.
        val wtf = File(root, "_forever_/WTF")
        assertTrue(!File(wtf, "Account").exists())
        val archive = File(wtf, ".forever-touch/LauncherProfiles.lua")
        assertTrue(archive.isFile)
        val output = recoverMobileProfiles(root).decodeToString().substringAfter("addon.recoveredProfiles = ")
        val recovered = parseLuaData("Restored=$output")["Restored"] as LuaTable
        val profiles = recovered["profiles"] as LuaTable
        val stored = profiles["Player-22-ABC"] as LuaTable
        assertEquals(stored, profiles["character:3/realm/händler"])
        assertEquals(2L, stored["mobileArcPage"])
        val right = (stored["mobileSlots"] as LuaTable)["right"] as LuaTable
        assertEquals(120L, (right[1L] as LuaTable)["id"])
        assertTrue(stored.containsKey("mobileArcPositions"))
        assertTrue(stored.containsKey("mobileArcPages"))
    }

    @Test fun validatesSessionChecksumAndNewestTransfer() {
        val data = "test".repeat(900).toByteArray()
        val start = frame(data, serial = 10)
        val last = frame(data, serial = 10, part = 1)
        val transfer = MobileArcTransfer(SESSION, previousSerial = 9)
        assertNull(transfer.readFrame { last[it] })
        assertEquals(data.decodeToString(), transfer.readFrame { start[it] }?.data)
        assertNull(MobileArcTransfer("0123456789abcdee").readFrame { start[it] })
        assertNull(MobileArcTransfer(SESSION, previousSerial = 10).readFrame { start[it] })
        val damaged = start.clone().apply { this[122] = palette(15) }
        val another = MobileArcTransfer(SESSION)
        assertNull(another.readFrame { last[it] })
        assertNull(another.readFrame { damaged[it] })
    }

    private fun frame(data: ByteArray, serial: Int, encoding: Int = 0, part: Int = 0): IntArray {
        val start = part * CHUNK_BYTES
        val length = minOf(data.size - start, CHUNK_BYTES)
        val bytes = ByteBuffer.allocate(28 + length).apply {
            put(byteArrayOf(70, 84, 1, encoding.toByte()))
            putLong(0x0123456789abcdef)
            putInt(serial)
            putInt(data.size)
            putInt(Adler32().apply { update(data) }.value.toInt())
            putShort(part.toShort())
            putShort(length.toShort())
            put(data, start, length)
        }.array()
        return IntArray(ARC_COLUMNS * ARC_ROWS).apply {
            for (i in 0 until 16) this[i] = palette(i)
            for ((i, byte) in bytes.withIndex()) {
                this[16 + i * 2] = palette((byte.toInt() and 255) ushr 4)
                this[17 + i * 2] = palette(byte.toInt() and 15)
            }
        }
    }

    // Simulate an RGB swap and non-linear display color conversion.
    private fun palette(i: Int): Int = (i % 2 * 255 shl 16) or
        (listOf(0, 105, 190, 255)[i / 2 % 4] shl 8) or (i / 8 * 255)

    private fun deflate(data: ByteArray): ByteArray {
        val deflater = Deflater(6, true)
        try {
            deflater.setInput(data)
            deflater.finish()
            val output = ByteArray(1024)
            val size = deflater.deflate(output)
            check(deflater.finished())
            return output.copyOf(size)
        } finally {
            deflater.end()
        }
    }

    private companion object {
        const val SESSION = "0123456789abcdef"
        const val CHUNK_BYTES = 3036
    }
}
