package app.gamenative.ui.screen.wow

import java.io.ByteArrayOutputStream

internal class LuaTable : LinkedHashMap<Any, Any>()

internal fun parseLuaData(text: String): LuaTable = SavedVariablesReader(text.removePrefix("\uFEFF")).read()

internal fun luaData(value: Any): String = buildString { appendLuaData(value) }

private fun StringBuilder.appendLuaData(value: Any) {
    when (value) {
        is LuaTable -> {
            append("{\n")
            for ((key, item) in value) {
                append('[')
                appendLuaData(key)
                append("]=")
                appendLuaData(item)
                append(",\n")
            }
            append('}')
        }
        is String -> {
            append('"')
            for (char in value) {
                when {
                    char == '"' || char == '\\' -> append('\\').append(char)
                    char.code < 32 || char.code == 127 -> append('\\').append(char.code.toString().padStart(3, '0'))
                    else -> append(char)
                }
            }
            append('"')
        }
        is Number, is Boolean -> append(value)
        else -> error("Unexpected SavedVariables value")
    }
}

// SavedVariables are text files, but recovery imports literals only. Running an
// old Lua file as an addon would also run any code placed in that file.
private class SavedVariablesReader(private val source: String) {
    private var offset = 0
    private val next: Char get() = source.getOrElse(offset) { '\u0000' }

    fun read(): LuaTable = LuaTable().apply {
        skipSpace()
        while (offset < source.length) {
            val name = token(IDENTIFIER)
            expect('=')
            val value = readValue(0)
            if (value == null) remove(name) else put(name, value)
            skipSpace()
            if (next == ';') offset++
            skipSpace()
        }
    }

    private fun readValue(depth: Int): Any? {
        skipSpace()
        return when (next) {
            '{' -> readTable(depth)
            '"', '\'' -> readString()
            '-', '.', in '0'..'9' -> readNumber()
            else -> readKeyword(token(IDENTIFIER))
        }
    }

    private fun readTable(depth: Int): LuaTable = LuaTable().apply {
        require(depth < 32)
        expect('{')
        var index = 1L
        skipSpace()
        while (next != '}') {
            val (key, value) = when (next) {
                '[' -> {
                    expect('[')
                    skipSpace()
                    val key = if (next == '"' || next == '\'') readString() else readNumber()
                    expect(']')
                    expect('=')
                    key to readValue(depth + 1)
                }
                in 'A'..'Z', in 'a'..'z', '_' -> {
                    val name = token(IDENTIFIER)
                    skipSpace()
                    if (next == '=') {
                        offset++
                        name to readValue(depth + 1)
                    } else {
                        index++ to readKeyword(name)
                    }
                }
                else -> index++ to readValue(depth + 1)
            }
            if (value == null) remove(key) else put(key, value)
            skipSpace()
            if (next == '}') break
            require(next == ',' || next == ';')
            offset++
            skipSpace()
        }
        expect('}')
    }

    private fun readString(): String {
        val delimiter = next
        offset++
        val value = ByteArrayOutputStream()
        while (offset < source.length && next != delimiter) {
            val start = offset
            while (offset < source.length && next != delimiter && next != '\\') {
                require(next != '\n' && next != '\r' && next != '\u0000')
                offset++
            }
            value.write(source.substring(start, offset).toByteArray())
            if (next != '\\') break
            offset++
            if (next in '0'..'9') {
                val first = offset
                while (offset - first < 3 && next in '0'..'9') offset++
                val byte = source.substring(first, offset).toInt()
                require(byte <= 255)
                value.write(byte)
            } else {
                val escaped = when (next) {
                    'a' -> 7
                    'b' -> 8
                    'f' -> 12
                    'n', '\n' -> 10
                    'r' -> 13
                    't' -> 9
                    'v' -> 11
                    '\\', '"', '\'' -> next.code
                    else -> error("Unrecognized Lua escape")
                }
                value.write(escaped)
                offset++
            }
        }
        require(next == delimiter)
        offset++
        return value.toByteArray().decodeToString(throwOnInvalidSequence = true)
    }

    private fun readNumber(): Number {
        val number = token(NUMBER)
        return number.toLongOrNull() ?: number.toDouble().also { require(it.isFinite()) }
    }

    private fun readKeyword(keyword: String): Boolean? = when (keyword) {
        "true" -> true
        "false" -> false
        "nil" -> null
        else -> error("Unexpected Lua value")
    }

    private fun token(pattern: Regex): String {
        skipSpace()
        val match = checkNotNull(pattern.matchAt(source, offset))
        offset += match.value.length
        return match.value
    }

    private fun expect(char: Char) {
        skipSpace()
        require(next == char)
        offset++
    }

    private fun skipSpace() {
        while (offset < source.length) {
            if (next.isWhitespace()) {
                offset++
            } else if (source.startsWith("--", offset)) {
                val newline = source.indexOf('\n', offset + 2)
                offset = if (newline < 0) source.length else newline + 1
            } else return
        }
    }

    private companion object {
        val IDENTIFIER = Regex("[A-Za-z_][A-Za-z_0-9]*")
        val NUMBER = Regex("-?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
    }
}
