package app.gamenative.ui.screen.wow

import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS

internal const val MOBILE_RECOVERY_FILE = "ForeverTouchRecovery.lua"
private const val MAX_SAVE_BYTES = 8 * 1024 * 1024L
private const val LAUNCHER_PROFILES = "ForeverTouchLauncherProfiles"
private val arcFields = listOf("mobileSlots", "mobileArcPositions", "mobileArcPages", "mobileArcPage", "order", "favorites")
private val profilePathLock = Any()

internal fun recoverMobileProfiles(gameRoot: File): ByteArray = synchronized(profilePathLock) {
    val wtf = mobileWtf(gameRoot)
    val backup = File(wtf, ".forever-touch")
    val archive = File(backup, "LauncherProfiles.lua")
    val canUseArchive = !Files.isSymbolicLink(backup.toPath()) && !Files.isSymbolicLink(archive.toPath())
    val previous = if (canUseArchive) readMobileSavedVariables(archive)?.get(LAUNCHER_PROFILES) as? LuaTable else null
    val profiles = previous?.get("profiles") as? LuaTable ?: LuaTable()
    val characters = previous?.get("characters") as? LuaTable ?: LuaTable()

    for (directory in listOf(File(wtf, "Account"), backup)) {
        if (!Files.isDirectory(directory.toPath(), NOFOLLOW_LINKS)) continue
        Files.walk(directory.toPath(), 5).use { files ->
            files.filter { Files.isRegularFile(it, NOFOLLOW_LINKS) }.forEach { path ->
                val parts = directory.toPath().relativize(path).toList().map { it.toString() }
                if (parts.size !in listOf(3, 5) || parts[parts.lastIndex - 1] != "SavedVariables" ||
                    parts.last() !in listOf("ForeverTouch.lua", "ForeverTouch.lua.bak")) return@forEach
                val saved = readMobileSavedVariables(path.toFile()) ?: return@forEach
                val account = saved["ForeverTouchProfiles"] as? LuaTable
                account?.forEach { (key, value) ->
                    if (key is String && (key.startsWith("Player-") || key.startsWith("character:"))) {
                        retainProfile(profiles, key, value)
                    }
                }
                if (parts.size == 5) {
                    val key = normalizeProfilePath(parts[1]) + "/" + normalizeProfilePath(parts[2])
                    retainProfile(characters, key, saved["ForeverTouchPreferences"])
                }
            }
        }
    }

    val recovered = luaData(LuaTable().apply { put("profiles", profiles); put("characters", characters) })
    if (canUseArchive && (profiles.isNotEmpty() || characters.isNotEmpty())) {
        writeMobileAddonFile(archive, "$LAUNCHER_PROFILES = $recovered\n".toByteArray())
    }
    "local _, addon = ...\naddon.recoveredProfiles = $recovered\n".toByteArray()
}

/** Commit the current character's profile without asking WoW to reload. */
internal fun saveMobileArcProfile(gameRoot: File, snapshot: String) = synchronized(profilePathLock) {
    val shot = parseLuaData(snapshot)["Arc"] as? LuaTable ?: error("Missing arc profile")
    val key = shot["key"] as? String ?: error("Missing arc character")
    val name = shot["nameKey"] as? String
    require(validProfileKey(key) && (name == null || validProfileKey(name)))
    val incoming = shot["profile"] as? LuaTable ?: error("Missing arc preferences")
    val revision = incoming["revision"] as? Long ?: error("Missing profile revision")
    val arcRevision = incoming["arcRevision"] as? Long ?: error("Missing arc revision")
    require(arcRevision in 0..revision)

    val archive = File(mobileWtf(gameRoot), ".forever-touch/LauncherProfiles.lua")
    check(!Files.isSymbolicLink(archive.parentFile!!.toPath()) && !Files.isSymbolicLink(archive.toPath()))
    val state = if (archive.exists()) {
        readMobileSavedVariables(archive)?.get(LAUNCHER_PROFILES) as? LuaTable ?: error("Invalid arc archive")
    } else LuaTable()
    val profiles = (state["profiles"] as? LuaTable ?: LuaTable()).also { state["profiles"] = it }
    state.putIfAbsent("characters", LuaTable())
    for (alias in listOfNotNull(key, name).distinct()) {
        val previous = profiles[alias] as? LuaTable
        check(previous == null || arcRevision(previous) <= arcRevision) { "A newer arc layout is already saved" }
        retainProfile(profiles, alias, incoming, preferIncomingArc = true)
    }
    val contents = "$LAUNCHER_PROFILES = ${luaData(state)}\n".toByteArray()
    require(contents.size <= MAX_SAVE_BYTES)
    writeMobileAddonFile(archive, contents, sync = true)
}

private fun mobileWtf(gameRoot: File): File = File(gameRoot, "${WowClientDownloader.FLAVOR_DIR}/WTF").canonicalFile

private fun validProfileKey(key: String): Boolean = key.length <= 256 && (
    key.matches(Regex("Player-[0-9]+-[0-9a-fA-F]+")) ||
        key.matches(Regex("character:[0-9]+/[^/\\p{Cntrl}]+/[^/\\p{Cntrl}]+"))
    )

private fun normalizeProfilePath(value: String): String = value.filterNot { it.isWhitespace() }
    .map { if (it in 'A'..'Z') it.lowercaseChar() else it }.joinToString("")

private fun retainProfile(profiles: LuaTable, key: String, value: Any?, preferIncomingArc: Boolean = false) {
    val incoming = value as? LuaTable ?: return
    if (incoming.isEmpty()) return
    val prior = profiles[key] as? LuaTable
    if (prior == null) {
        profiles[key] = incoming
        return
    }
    val base = if (revision(incoming) > revision(prior) ||
        (preferIncomingArc && revision(incoming) == revision(prior))) incoming else prior
    val other = if (base === prior) incoming else prior
    profiles[key] = if (arcRevision(other) > arcRevision(base) || (preferIncomingArc && other === incoming)) {
        LuaTable().apply {
            putAll(base)
            for (field in arcFields) {
                val saved = other[field]
                if (saved == null) remove(field) else put(field, saved)
            }
            put("arcRevision", arcRevision(other))
        }
    } else base
}

private fun revision(table: LuaTable): Long = (table["revision"] as? Number)?.toLong() ?: 0L

private fun arcRevision(table: LuaTable): Long = (table["arcRevision"] as? Number)?.toLong()
    ?: if (arcFields.any(table::containsKey)) revision(table) else -1L

private fun readMobileSavedVariables(file: File): LuaTable? = runCatching {
    if (!file.isFile || file.length() !in 1..MAX_SAVE_BYTES) null else parseLuaData(file.readText())
}.getOrNull()
