package app.gamenative.ui.screen.wow

import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import kotlin.io.path.name

private const val PROFILE = "ForeverTouch.lua"
private const val PROFILE_LIMIT = 8 * 1024 * 1024L

internal fun checkpointMobileProfiles(gameRoot: File) {
    val wtf = File(gameRoot, "${WowClientDownloader.FLAVOR_DIR}/WTF").canonicalFile
    val accounts = File(wtf, "Account")
    val checkpoints = File(wtf, ".forever-touch")
    val paths = profilePaths(accounts) + profilePaths(checkpoints)
    for (path in paths) {
        val current = File(accounts, path)
        val saved = File(checkpoints, path)
        val gameBackup = File(accounts, "$path.bak")
        if (!current.canonicalFile.toPath().startsWith(accounts.toPath()) ||
            !saved.canonicalFile.toPath().startsWith(checkpoints.toPath()) ||
            !gameBackup.canonicalFile.toPath().startsWith(accounts.toPath())
        ) continue

        val data = if (current.isFile && current.length() > 0L) {
            readProfile(current)
        } else {
            val recovered = listOf(gameBackup, saved).sortedByDescending(File::lastModified)
                .firstNotNullOfOrNull(::readProfile)
            if (recovered != null) writeMobileAddonFile(current, recovered)
            recovered
        }
        if (data != null) writeMobileAddonFile(saved, data)
    }
}

private fun profilePaths(directory: File): Set<String> {
    if (!Files.isDirectory(directory.toPath(), NOFOLLOW_LINKS)) return emptySet()
    return Files.walk(directory.toPath(), 5).use { paths ->
        paths.iterator().asSequence()
            .filter { Files.isRegularFile(it, NOFOLLOW_LINKS) }
            .map { directory.toPath().relativize(it) }
            .filter { (it.nameCount == 3 || it.nameCount == 5) && it.parent.name == "SavedVariables" }
            .filter { it.name == PROFILE || it.name == "$PROFILE.bak" }
            .map(Path::toString)
            .map { it.removeSuffix(".bak") }
            .toSet()
    }
}

private fun readProfile(file: File): ByteArray? {
    if (!file.isFile || file.length() !in 1..PROFILE_LIMIT) return null
    val data = file.readBytes()
    val text = data.toString(Charsets.UTF_8).trim().removePrefix("\uFEFF")
    val hasProfile = text.startsWith("ForeverTouchProfiles = {") ||
        text.startsWith("ForeverTouchPreferences = {")
    return data.takeIf { hasProfile && text.endsWith('}') }
}
