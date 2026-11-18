package app.gamenative.ui.screen.wow

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import app.gamenative.R
import app.gamenative.ui.util.SnackbarManager

private const val BATTLE_NET_PACKAGE = "com.blizzard.messenger"

internal fun openBattleNetApp(context: Context, notifyIfUnavailable: Boolean = true): Boolean {
    val intent = context.packageManager.getLaunchIntentForPackage(BATTLE_NET_PACKAGE)
    if (intent != null) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return true
        } catch (_: ActivityNotFoundException) {
            // The app may have been uninstalled or disabled after resolving the intent.
        } catch (_: SecurityException) {
            // The app may be restricted by the device's profile.
        }
    }
    if (notifyIfUnavailable) SnackbarManager.show(context.getString(R.string.mobile_battle_net_unavailable))
    return false
}
