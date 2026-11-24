package app.gamenative.ui.screen.xserver

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import app.gamenative.R

private const val CHAT_MESSAGE_BYTES = 255
private val chatInk = Color(0xFFF0F5FF)
private val chatHint = Color(0xFFABB9D0)
private val chatAccent = Color(0xFF8EB4FF)

/** Transfer UTF-8 through the guest's existing ASCII keyboard transport. */
internal fun fullscreenChatMessagePacket(draft: String): String? {
    if (draft.length > CHAT_MESSAGE_BYTES) return null
    val message = buildString(draft.length) {
        draft.forEach { append(if (it.isISOControl()) ' ' else it) }
    }
    if (message.isBlank()) return null
    val bytes = message.encodeToByteArray()
    if (bytes.size > CHAT_MESSAGE_BYTES) return null
    val digits = "0123456789abcdef"
    return buildString(4 + bytes.size * 2) {
        append('m').append(bytes.size.toString().padStart(3, '0'))
        for (byte in bytes) {
            val value = byte.toInt() and 255
            append(digits[value shr 4]).append(digits[value and 15])
        }
    }
}

@Composable
internal fun MobileFullscreenChatInput(
    modifier: Modifier = Modifier,
    onFocusChanged: (Boolean) -> Unit,
    onSend: (String) -> Boolean,
    onClose: () -> Unit,
) {
    var draft by remember { mutableStateOf("") }
    var focused by remember { mutableStateOf(false) }
    val packet = remember(draft) { fullscreenChatMessagePacket(draft) }
    val tooLong = packet == null && draft.isNotBlank()
    val keyboard = LocalSoftwareKeyboardController.current
    val updateFocus by rememberUpdatedState(onFocusChanged)
    DisposableEffect(keyboard) {
        onDispose {
            updateFocus(false)
            if (focused) keyboard?.hide()
        }
    }

    fun submit() {
        // Read the current state so an IME action and a button tap cannot submit the same draft twice.
        val pending = fullscreenChatMessagePacket(draft) ?: return
        if (onSend(pending)) draft = ""
    }

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        color = Color(0xFF151E2B),
        border = BorderStroke(1.dp, if (focused) chatAccent else Color(0xFF35465D)),
        contentColor = chatInk,
    ) {
        Column {
            Row(
                modifier = Modifier.padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onClose, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Filled.Close, stringResource(R.string.mobile_chat_window), tint = chatHint)
                }
                BasicTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = chatInk),
                    cursorBrush = SolidColor(chatAccent),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Send,
                    ),
                    keyboardActions = KeyboardActions(onSend = { submit() }),
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp)
                        .onFocusChanged { state ->
                            focused = state.isFocused
                            onFocusChanged(focused)
                        }
                        .onPreviewKeyEvent { event ->
                            if (event.key != Key.Enter && event.key != Key.NumPadEnter) false else {
                                if (event.type == KeyEventType.KeyUp) submit()
                                true
                            }
                        },
                    decorationBox = { input ->
                        Box(contentAlignment = Alignment.CenterStart) {
                            if (draft.isEmpty()) Text(stringResource(R.string.mobile_chat), color = chatHint)
                            input()
                        }
                    },
                )
                IconButton(
                    onClick = ::submit,
                    enabled = packet != null,
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(
                        Icons.Filled.Send,
                        contentDescription = stringResource(R.string.mobile_chat_send),
                        tint = if (packet != null) chatAccent else chatHint.copy(alpha = .42f),
                    )
                }
            }
            if (tooLong) {
                Text(
                    stringResource(R.string.mobile_chat_too_long),
                    modifier = Modifier.padding(start = 14.dp, end = 12.dp, bottom = 8.dp),
                    color = Color(0xFFFFB8AD),
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }
}
