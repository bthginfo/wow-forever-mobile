package app.gamenative.ui.screen.wow

import android.content.Context
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING

internal fun installMobileAddon(context: Context, gameRoot: File) {
    val addon = File(gameRoot, "${WowClientDownloader.FLAVOR_DIR}/Interface/AddOns/ForeverTouch")
    check(addon.isDirectory || addon.mkdirs()) { "Could not create the Forever Touch add-on folder." }

    val language = AppLanguage.fromTag(context.resources.configuration.locales[0].language) ?: AppLanguage.ENGLISH
    val manifest = context.assets.open("ForeverTouch/ForeverTouch.toc").bufferedReader().use { toc ->
        "## X-ForeverTouch-Language: ${language.tag}\n## X-ForeverTouch-Keyboard: native\n${toc.readText()}".toByteArray()
    }
    val scripts = listOf(
        "ForeverTouchActions.lua", "ForeverTouchPicker.lua", "ForeverTouchChatHistory.lua",
        "ForeverTouchChat.lua", "ForeverTouchMobileLayout.lua", "ChatCorner.tga",
    ).map { name ->
        name to context.assets.open("ForeverTouch/$name").use { it.readBytes() }
    }
    // Forever prefers the Camelot manifest installed by the HUD ZIP. Refresh it together with the fallback.
    val files = scripts + listOf("ForeverTouch.toc" to manifest, "ForeverTouch_Camelot.toc" to manifest)
    for ((name, bundled) in files) {
        writeMobileAddonFile(File(addon, name), bundled)
    }
}

internal fun writeMobileAddonFile(destination: File, contents: ByteArray) {
    if (destination.isFile && destination.length() == contents.size.toLong() &&
        destination.readBytes().contentEquals(contents)
    ) return
    val directory = checkNotNull(destination.parentFile)
    check(directory.isDirectory || directory.mkdirs()) { "Could not create ${directory.name}." }
    val staging = File.createTempFile(destination.name, ".part", directory)
    try {
        staging.writeBytes(contents)
        try {
            Files.move(staging.toPath(), destination.toPath(), ATOMIC_MOVE, REPLACE_EXISTING)
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(staging.toPath(), destination.toPath(), REPLACE_EXISTING)
        }
    } finally {
        staging.delete()
    }
}
