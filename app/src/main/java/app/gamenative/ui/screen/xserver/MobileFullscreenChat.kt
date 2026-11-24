package app.gamenative.ui.screen.xserver

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.KeyboardHide
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.PlatformTextInputInterceptor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import app.gamenative.R
import app.gamenative.ui.component.InlineKey
import app.gamenative.ui.component.InlineKeyboard
import kotlinx.coroutines.awaitCancellation

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

internal fun insertChatText(value: TextFieldValue, insert: String): TextFieldValue {
    val start = value.selection.min
    val end = value.selection.max
    val text = insert.map { if (it.isISOControl()) ' ' else it }.joinToString("")
    return TextFieldValue(value.text.replaceRange(start, end, text), TextRange(start + text.length))
}

internal fun editChatText(value: TextFieldValue, key: InlineKey): TextFieldValue {
    val start = value.selection.min
    val end = value.selection.max
    val hasSelection = start != end
    return when (key) {
        InlineKey.BACKSPACE -> {
            val from = if (hasSelection || start == 0) start else value.text.offsetByCodePoints(start, -1)
            TextFieldValue(value.text.removeRange(from, end), TextRange(from))
        }
        InlineKey.LEFT -> {
            val cursor = if (hasSelection || start == 0) start else value.text.offsetByCodePoints(start, -1)
            value.copy(selection = TextRange(cursor))
        }
        InlineKey.RIGHT -> {
            val cursor = if (hasSelection || end == value.text.length) end else value.text.offsetByCodePoints(end, 1)
            value.copy(selection = TextRange(cursor))
        }
        else -> value
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
internal fun MobileFullscreenChatInput(
    modifier: Modifier = Modifier,
    keyboardVisible: Boolean,
    onKeyboardVisibility: (Boolean) -> Unit,
    clipboardText: () -> CharSequence?,
    onFocusChanged: (Boolean) -> Unit,
    onSend: (String) -> Boolean,
    onClose: () -> Unit,
) {
    var draft by remember { mutableStateOf(TextFieldValue()) }
    var focused by remember { mutableStateOf(false) }
    val packet = remember(draft.text) { fullscreenChatMessagePacket(draft.text) }
    val tooLong = packet == null && draft.text.isNotBlank()
    val focusRequester = remember { FocusRequester() }
    val fieldTouches = remember { MutableInteractionSource() }
    val blockIme = remember { PlatformTextInputInterceptor { _, _ -> awaitCancellation() } }
    val updateFocus by rememberUpdatedState(onFocusChanged)
    val setKeyboardVisibility by rememberUpdatedState(onKeyboardVisibility)
    LaunchedEffect(fieldTouches) {
        fieldTouches.interactions.collect { interaction ->
            if (interaction is PressInteraction.Release) setKeyboardVisibility(true)
        }
    }
    LaunchedEffect(keyboardVisible) { if (keyboardVisible) focusRequester.requestFocus() }
    DisposableEffect(Unit) { onDispose { updateFocus(false) } }

    fun submit() {
        val pending = fullscreenChatMessagePacket(draft.text) ?: return
        if (onSend(pending)) draft = TextFieldValue()
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
                CompositionLocalProvider(LocalSoftwareKeyboardController provides null) {
                    InterceptPlatformTextInput(blockIme) {
                        BasicTextField(
                            value = draft,
                            onValueChange = { draft = it },
                            singleLine = true,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(color = chatInk),
                            cursorBrush = SolidColor(chatAccent),
                            interactionSource = fieldTouches,
                            modifier = Modifier.weight(1f).heightIn(min = 48.dp)
                                .focusRequester(focusRequester)
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
                                    if (draft.text.isEmpty()) Text(stringResource(R.string.mobile_chat), color = chatHint)
                                    input()
                                }
                            },
                        )
                    }
                }
                IconButton(
                    onClick = { onKeyboardVisibility(!keyboardVisible) },
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(
                        if (keyboardVisible) Icons.Filled.KeyboardHide else Icons.Filled.Keyboard,
                        stringResource(if (keyboardVisible) R.string.mobile_keyboard_hide else R.string.keyboard),
                        tint = chatHint,
                    )
                }
                if (!keyboardVisible) {
                    IconButton(onClick = ::submit, enabled = packet != null, modifier = Modifier.size(48.dp)) {
                        Icon(Icons.Filled.Send, stringResource(R.string.mobile_chat_send), tint = chatAccent)
                    }
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
            if (keyboardVisible) {
                InlineKeyboard(
                    enterLabel = R.string.mobile_chat_send,
                    onText = { draft = insertChatText(draft, it) },
                    onKey = { key ->
                        when (key) {
                            InlineKey.ENTER -> submit()
                            InlineKey.PASTE -> clipboardText()?.let { draft = insertChatText(draft, it.toString()) }
                            else -> draft = editChatText(draft, key)
                        }
                    },
                )
            }
        }
    }
}
