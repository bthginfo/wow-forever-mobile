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
        "## X-ForeverTouch-Language: ${language.tag}\n${toc.readText()}".toByteArray()
    }
    val scripts = listOf("ForeverTouchActions.lua", "ForeverTouchPicker.lua", "ForeverTouchMobileLayout.lua").map { name ->
        name to context.assets.open("ForeverTouch/$name").use { it.readBytes() }
    }
    // Forever prefers the Camelot manifest installed by the HUD ZIP. Refresh it together with the fallback.
    val files = scripts + listOf("ForeverTouch.toc" to manifest, "ForeverTouch_Camelot.toc" to manifest)
    for ((name, bundled) in files) {
        val installed = File(addon, name)
        if (installed.isFile && installed.length() == bundled.size.toLong() &&
            installed.readBytes().contentEquals(bundled)
        ) continue

        val staging = File.createTempFile(name, ".part", addon)
        try {
            staging.writeBytes(bundled)
            try {
                Files.move(staging.toPath(), installed.toPath(), ATOMIC_MOVE, REPLACE_EXISTING)
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(staging.toPath(), installed.toPath(), REPLACE_EXISTING)
            }
        } finally {
            staging.delete()
        }
    }
}
