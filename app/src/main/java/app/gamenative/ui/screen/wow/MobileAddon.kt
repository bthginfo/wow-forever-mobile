package app.gamenative.ui.screen.wow

import android.content.Context
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING

private const val INPUT_MODE_FILE = "ForeverTouchInputMode.lua"

private fun addonDirectory(gameRoot: File) =
    File(gameRoot, "${WowClientDownloader.FLAVOR_DIR}/Interface/AddOns/ForeverTouch")

internal fun updateMobileAddonInputMode(gameRoot: File, desktop: Boolean) {
    val addon = addonDirectory(gameRoot)
    val code = "local _, addon = ...\naddon.desktopInput = $desktop\n"
    installAddonFile(File(addon, INPUT_MODE_FILE), code.toByteArray())
}

internal fun installMobileAddon(context: Context, gameRoot: File) {
    val addon = addonDirectory(gameRoot)
    check(addon.isDirectory || addon.mkdirs()) { "Could not create the Forever Touch add-on folder." }

    val language = AppLanguage.fromTag(context.resources.configuration.locales[0].language) ?: AppLanguage.ENGLISH
    val manifest = context.assets.open("ForeverTouch/ForeverTouch.toc").bufferedReader().use { toc ->
        "## X-ForeverTouch-Language: ${language.tag}\n${toc.readText()}".toByteArray()
    }
    val scripts = listOf("ForeverTouchActions.lua", "ForeverTouchPicker.lua", "ForeverTouchMobileLayout.lua").map { name ->
        name to context.assets.open("ForeverTouch/$name").use { it.readBytes() }
    }
    // Forever prefers the Camelot manifest installed by the HUD ZIP. Refresh it together with the fallback.
    updateMobileAddonInputMode(gameRoot, HardwareInput.connected().desktop)
    val files = scripts + listOf("ForeverTouch.toc" to manifest, "ForeverTouch_Camelot.toc" to manifest)
    for ((name, bundled) in files) {
        installAddonFile(File(addon, name), bundled)
    }
}

private fun installAddonFile(installed: File, bundled: ByteArray) {
    if (installed.isFile && installed.length() == bundled.size.toLong() &&
        installed.readBytes().contentEquals(bundled)
    ) return

    val staging = File.createTempFile(installed.name, ".part", installed.parentFile)
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
