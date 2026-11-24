package app.gamenative.ui.component

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.gamenative.R

internal enum class InlineKey { BACKSPACE, ENTER, PASTE, LEFT, RIGHT, TAB }

private val keyFace = Color(0xFF303D51)
private val actionFace = Color(0xFF223044)
private val keyInk = Color(0xFFF0F5FF)
private val accentFace = Color(0xFF90B7FF)
private val symbolRows = listOf("1234567890", "@#$%&-+()_", "!?.,:;'\"/\\=", "[]{}<>*^~`|")
private val germanRows = listOf("qwertzuiopü", "asdfghjklöä", "yxcvbnmß")
private val englishRows = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")

@Composable
internal fun InlineKeyboard(
    onText: (String) -> Unit,
    onKey: (InlineKey) -> Unit,
    modifier: Modifier = Modifier,
    @StringRes enterLabel: Int = R.string.mobile_keyboard_enter,
    allowGerman: Boolean = true,
    showTab: Boolean = false,
) {
    val locale = LocalConfiguration.current.locales[0]
    var german by remember(locale) { mutableStateOf(allowGerman && locale.language == "de") }
    var symbols by remember { mutableStateOf(false) }
    // 0 is lowercase, 1 applies to the next letter, 2 keeps uppercase enabled.
    var shift by remember { mutableIntStateOf(0) }
    val rows = when {
        symbols -> symbolRows
        german -> germanRows
        else -> englishRows
    }
    val keyHeight = if (symbols) 28.dp else 35.dp

    Column(
        modifier = modifier.fillMaxWidth().background(Color(0xFF131C29)).padding(5.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        rows.forEachIndexed { index, row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                val lastRow = index == rows.lastIndex
                if (!symbols && lastRow) {
                    KeyboardKey(if (shift == 2) "⇪" else "⇧", keyHeight, 1.15f, if (shift > 0) accentFace else actionFace,
                        stringResource(R.string.mobile_keyboard_shift)) { shift = (shift + 1) % 3 }
                }
                row.forEach { letter ->
                    val text = if (shift > 0 && !symbols) {
                        if (letter == 'ß') "ẞ" else letter.uppercase()
                    } else letter.toString()
                    KeyboardKey(text, keyHeight) {
                        onText(text)
                        if (shift == 1 && !symbols) shift = 0
                    }
                }
                if (lastRow) {
                    KeyboardKey("⌫", keyHeight, 1.2f, actionFace, stringResource(R.string.mobile_keyboard_backspace)) {
                        onKey(InlineKey.BACKSPACE)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            KeyboardKey(if (symbols) "ABC" else "123", keyHeight, 1.25f, actionFace) { symbols = !symbols }
            if (allowGerman) {
                KeyboardKey(if (german) "DE" else "EN", keyHeight, 1f, actionFace,
                    stringResource(R.string.mobile_keyboard_language)) {
                    german = !german
                    symbols = false
                }
            }
            Box(
                modifier = Modifier.weight(1f).height(keyHeight).clip(RoundedCornerShape(6.dp))
                    .background(actionFace).clickable(role = Role.Button) { onKey(InlineKey.PASTE) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.ContentPaste, stringResource(R.string.mobile_paste), tint = keyInk)
            }
            if (showTab) {
                KeyboardKey("Tab", keyHeight, 1f, actionFace) { onKey(InlineKey.TAB) }
            } else {
                KeyboardKey("@", keyHeight, 1f, actionFace) { onText("@") }
            }
            KeyboardKey("␣", keyHeight, 3.6f, description = stringResource(R.string.mobile_keyboard_space)) { onText(" ") }
            KeyboardKey(".", keyHeight, .85f) { onText(".") }
            KeyboardKey("‹", keyHeight, .85f, actionFace, stringResource(R.string.mobile_keyboard_left)) { onKey(InlineKey.LEFT) }
            KeyboardKey("›", keyHeight, .85f, actionFace, stringResource(R.string.mobile_keyboard_right)) { onKey(InlineKey.RIGHT) }
            KeyboardKey(stringResource(enterLabel), keyHeight, 1.8f, accentFace) { onKey(InlineKey.ENTER) }
        }
    }
}

@Composable
private fun RowScope.KeyboardKey(
    text: String,
    height: Dp,
    weight: Float = 1f,
    color: Color = keyFace,
    description: String? = null,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier.weight(weight).height(height).clip(RoundedCornerShape(6.dp)).background(color)
            .then(if (description == null) Modifier else Modifier.semantics { contentDescription = description })
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            color = if (color == accentFace) Color(0xFF112441) else keyInk,
            maxLines = 1,
        )
    }
}
