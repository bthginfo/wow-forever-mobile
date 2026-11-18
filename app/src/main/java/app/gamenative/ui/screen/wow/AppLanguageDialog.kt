package app.gamenative.ui.screen.wow

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import app.gamenative.R

internal enum class AppLanguage(val tag: String, val displayName: String) {
    ENGLISH("en", "English"),
    GERMAN("de", "Deutsch");

    companion object {
        fun fromTag(tag: String): AppLanguage? = entries.find { it.tag == tag }
    }
}

@Composable
internal fun AppLanguageDialog(
    current: AppLanguage?,
    saving: Boolean,
    saveFailed: Boolean,
    onSelect: (AppLanguage) -> Unit,
    onDismiss: () -> Unit,
) {
    val canDismiss = current != null && !saving
    AlertDialog(
        onDismissRequest = { if (canDismiss) onDismiss() },
        properties = DialogProperties(dismissOnBackPress = canDismiss, dismissOnClickOutside = canDismiss),
        title = { Text(stringResource(R.string.mobile_app_language)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (saveFailed) {
                    Text(stringResource(R.string.mobile_language_save_failed), color = MaterialTheme.colorScheme.error)
                }
                AppLanguage.entries.forEach { language ->
                    OutlinedButton(
                        onClick = { onSelect(language) },
                        enabled = !saving,
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(language.displayName) }
                }
            }
        },
        confirmButton = {
            if (current != null) {
                TextButton(onClick = onDismiss, enabled = canDismiss) { Text(stringResource(R.string.cancel)) }
            }
        },
    )
}
