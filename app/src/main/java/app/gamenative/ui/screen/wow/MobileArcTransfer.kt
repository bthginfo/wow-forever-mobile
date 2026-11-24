package app.gamenative.ui.screen.wow

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.zip.Adler32
import java.util.zip.Inflater
import java.util.zip.InflaterInputStream

internal const val MOBILE_ARC_SESSION = "mobileArcSession"
internal const val ARC_COLUMNS = 96
internal const val ARC_ROWS = 64
private const val PALETTE_SIZE = 16
private const val HEADER_SIZE = 28
private const val CHUNK_SIZE = (ARC_COLUMNS * ARC_ROWS - PALETTE_SIZE) / 2 - HEADER_SIZE
private const val MAX_PACKED_BYTES = 64 * 1024
private const val MAX_PROFILE_BYTES = 512 * 1024

internal fun newMobileArcSession(): String = ByteArray(8).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }

internal data class MobileArcSnapshot(val serial: Int, val data: String)

/** Decodes the addon's temporary color frame and accepts a complete, current-session snapshot. */
internal class MobileArcTransfer(session: String, private val previousSerial: Int? = null) {
    private val nonce = session.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private var header: Header? = null
    private var chunks = emptyArray<ByteArray?>()

    private data class Header(val serial: Int, val encoding: Int, val size: Int, val checksum: Int)

    fun readFrame(pixel: (Int) -> Int): MobileArcSnapshot? {
        val palette = IntArray(PALETTE_SIZE, pixel)
        // Flat colors identify each symbol even after color conversion or a red/blue swap.
        for (i in 1 until PALETTE_SIZE) {
            if ((0 until i).any { colorDistance(palette[it], palette[i]) < 400 }) return null
        }
        val headerBytes = ByteArray(HEADER_SIZE) { readByte(it, palette, pixel) }
        val input = ByteBuffer.wrap(headerBytes)
        if (input.get() != 70.toByte() || input.get() != 84.toByte() || input.get() != 1.toByte()) return null
        val encoding = input.get().toInt()
        if (encoding !in 0..1 || nonce.size != 8 || nonce.any { it != input.get() }) return null
        val next = Header(input.int, encoding, input.int, input.int)
        if (next.size !in 1..MAX_PACKED_BYTES || (previousSerial != null && next.serial - previousSerial <= 0)) return null
        val count = (next.size + CHUNK_SIZE - 1) / CHUNK_SIZE
        val part = input.short.toInt()
        val length = input.short.toInt()
        if (part !in 0 until count || length != minOf(CHUNK_SIZE, next.size - part * CHUNK_SIZE)) return null

        if (next != header) {
            header = next
            chunks = arrayOfNulls(count)
        }
        chunks[part] = ByteArray(length) { readByte(HEADER_SIZE + it, palette, pixel) }
        if (chunks.any { it == null }) return null
        val data = ByteArrayOutputStream(next.size).apply { chunks.forEach { write(checkNotNull(it)) } }.toByteArray()
        if (Adler32().apply { update(data) }.value.toInt() != next.checksum) return null
        val plain = if (encoding == 0) data else inflateProfile(data) ?: return null
        val text = runCatching { plain.decodeToString(throwOnInvalidSequence = true) }.getOrNull() ?: return null
        return MobileArcSnapshot(next.serial, text)
    }
}

private fun readByte(index: Int, palette: IntArray, pixel: (Int) -> Int): Byte {
    fun symbol(color: Int): Int {
        var best = 0
        var distance = Int.MAX_VALUE
        for (i in palette.indices) {
            val candidate = colorDistance(palette[i], color)
            if (candidate < distance) {
                best = i
                distance = candidate
            }
        }
        return best
    }
    val offset = PALETTE_SIZE + index * 2
    return ((symbol(pixel(offset)) shl 4) or symbol(pixel(offset + 1))).toByte()
}

private fun colorDistance(a: Int, b: Int): Int {
    val r = ((a ushr 16) and 255) - ((b ushr 16) and 255)
    val g = ((a ushr 8) and 255) - ((b ushr 8) and 255)
    val blue = (a and 255) - (b and 255)
    return r * r + g * g + blue * blue
}

private fun inflateProfile(data: ByteArray): ByteArray? {
    // The client defaults to Deflate. Accept raw streams and zlib-wrapped ones.
    for (raw in listOf(true, false)) {
        val inflater = Inflater(raw)
        try {
            val result = runCatching {
                InflaterInputStream(ByteArrayInputStream(data), inflater).use { input ->
                    val buffer = ByteArray(4096)
                    val output = ByteArrayOutputStream()
                    while (true) {
                        val size = input.read(buffer)
                        if (size < 0) break
                        require(output.size() + size <= MAX_PROFILE_BYTES)
                        output.write(buffer, 0, size)
                    }
                    check(inflater.finished())
                    output.toByteArray()
                }
            }.getOrNull()
            if (result != null) return result
        } finally {
            inflater.end()
        }
    }
    return null
}
