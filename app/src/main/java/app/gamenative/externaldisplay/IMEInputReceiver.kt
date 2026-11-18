package app.gamenative.externaldisplay

import android.content.ClipboardManager
import android.content.Context
import android.view.KeyEvent
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import app.gamenative.R
import app.gamenative.ui.util.SnackbarManager
import com.winlator.xserver.XKeycode
import com.winlator.xserver.Pointer
import com.winlator.xserver.XServer
import kotlinx.coroutines.delay
import timber.log.Timber

/**
 * Invisible view that receives IME (soft keyboard) input from Android system keyboard
 * and forwards it to XServer as keyboard events for the game.
 * 
 * This is needed when the system keyboard is pinned to the external display
 */
class IMEInputReceiver(
    context: Context,
    private val xServer: XServer,
    private val displayContext: Context = context,
) : FrameLayout(context) {

    val screenWidth: Int get() = xServer.screenInfo.width.toInt()
    val screenHeight: Int get() = xServer.screenInfo.height.toInt()

    suspend fun clickAt(x: Int, y: Int) {
        xServer.injectPointerMove(x, y)
        delay(60)
        xServer.injectPointerButtonPress(Pointer.Button.BUTTON_LEFT)
        delay(80)
        xServer.injectPointerButtonRelease(Pointer.Button.BUTTON_LEFT)
        delay(60)
    }

    fun movePointerTo(x: Int, y: Int) {
        xServer.injectPointerMove(x, y)
    }

    companion object {
        private val SHIFTED_SYMBOLS = setOf(
            ')', '!', '@', '#', '$', '%', '^', '&', '*', '(',
            '_', '+', '{', '}', '|', ':', '"', '<', '>', '?', '~',
        )
    }

    private var imeSessionActive = false
    private var onChatSend: (() -> Unit)? = null

    init {
        isFocusable = false
        isFocusableInTouchMode = false
    }

    override fun onCheckIsTextEditor(): Boolean {
        return imeSessionActive && hasFocus()
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        if (!imeSessionActive || !hasFocus()) {
            Timber.d(
                "IMEInputReceiver: onCreateInputConnection ignored (active=$imeSessionActive, hasFocus=${hasFocus()})",
            )
            return BaseInputConnection(this, false)
        }

        Timber.d("IMEInputReceiver: onCreateInputConnection called!")
        // Disable autocomplete/suggestions so each key commits immediately
        outAttrs.inputType = EditorInfo.TYPE_CLASS_TEXT or 
                             EditorInfo.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
                             EditorInfo.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        val chatSend = onChatSend
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or 
                              EditorInfo.IME_FLAG_NO_EXTRACT_UI or
                              EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or
                              (if (chatSend != null) EditorInfo.IME_ACTION_SEND else EditorInfo.IME_ACTION_NONE)
        
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                if (!imeSessionActive || chatSend !== onChatSend) return false
                editable?.clear()
                if (text != null) {
                    if (chatSend == null) typeText(text)
                    else if (text.toString() == "\n") chatSend()
                    else typeText(normalizeMobileChat(text))
                }
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                if (!imeSessionActive || chatSend !== onChatSend) return false
                Timber.d("IMEInputReceiver: deleteSurroundingText called")
                if (beforeLength > 0) {
                    repeat(beforeLength.coerceAtMost(256)) {
                        xServer.injectKeyPress(XKeycode.KEY_BKSP, 0, false)
                        xServer.injectKeyRelease(XKeycode.KEY_BKSP)
                    }
                    Timber.v("IMEInputReceiver: Sent backspace x$beforeLength")
                }
                return true
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean {
                if (!imeSessionActive || chatSend !== onChatSend) return false
                if (event.keyCode == KeyEvent.KEYCODE_ENTER && chatSend != null) {
                    if (event.action == KeyEvent.ACTION_UP) chatSend()
                    return true
                }
                if (event.keyCode == KeyEvent.KEYCODE_DEL || event.keyCode == KeyEvent.KEYCODE_ENTER) {
                    return xServer.keyboard.onKeyEvent(event)
                }
                return super.sendKeyEvent(event)
            }

            override fun performEditorAction(actionCode: Int): Boolean {
                if (chatSend != null && imeSessionActive && chatSend === onChatSend && actionCode == EditorInfo.IME_ACTION_SEND) {
                    chatSend()
                    return true
                }
                return super.performEditorAction(actionCode)
            }
        }
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        Timber.d("IMEInputReceiver: onWindowFocusChanged: $hasWindowFocus")
        if (hasWindowFocus && imeSessionActive && !hasFocus()) {
            post { requestFocus() }
        }
    }

    private data class KeyDispatch(
        val keyCode: Int,
        val requiresShift: Boolean,
    )

    fun typeText(text: CharSequence) {
        text.forEach(::sendCharacterToGame)
    }

    fun clipboardText(): CharSequence? {
        val manager = context.getSystemService(ClipboardManager::class.java)
        val clip = manager?.primaryClip ?: return null
        return if (clip.itemCount > 0) clip.getItemAt(0).text else null
    }

    fun pasteFromClipboard(chat: Boolean = false): Boolean {
        val copied = clipboardText()
        val text = if (chat && copied != null) normalizeMobileChat(copied) else copied
        if (text.isNullOrEmpty()) {
            SnackbarManager.show(context.getString(R.string.mobile_clipboard_empty))
            return false
        }
        if (text.length > 256 || text.any { it.isISOControl() || charToKeyDispatch(it) == null }) {
            SnackbarManager.show(context.getString(R.string.mobile_clipboard_unsupported))
            return false
        }
        typeText(text)
        return true
    }

    private fun sendCharacterToGame(char: Char) {
        val keyDispatch = charToKeyDispatch(char)
        if (keyDispatch != null) {
            val metaState = if (keyDispatch.requiresShift) KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON else 0
            val downEvent = KeyEvent(
                0L,
                0L,
                KeyEvent.ACTION_DOWN,
                keyDispatch.keyCode,
                0,
                metaState,
            )
            xServer.keyboard.onKeyEvent(downEvent)

            val upEvent = KeyEvent(
                0L,
                0L,
                KeyEvent.ACTION_UP,
                keyDispatch.keyCode,
                0,
                metaState,
            )
            xServer.keyboard.onKeyEvent(upEvent)

        }
    }

    private fun charToKeyDispatch(char: Char): KeyDispatch? {
        val isUppercaseLetter = char in 'A'..'Z'
        val normalizedChar = if (isUppercaseLetter) char.lowercaseChar() else char

        val keyCode = when (normalizedChar) {
            'a' -> KeyEvent.KEYCODE_A
            'b' -> KeyEvent.KEYCODE_B
            'c' -> KeyEvent.KEYCODE_C
            'd' -> KeyEvent.KEYCODE_D
            'e' -> KeyEvent.KEYCODE_E
            'f' -> KeyEvent.KEYCODE_F
            'g' -> KeyEvent.KEYCODE_G
            'h' -> KeyEvent.KEYCODE_H
            'i' -> KeyEvent.KEYCODE_I
            'j' -> KeyEvent.KEYCODE_J
            'k' -> KeyEvent.KEYCODE_K
            'l' -> KeyEvent.KEYCODE_L
            'm' -> KeyEvent.KEYCODE_M
            'n' -> KeyEvent.KEYCODE_N
            'o' -> KeyEvent.KEYCODE_O
            'p' -> KeyEvent.KEYCODE_P
            'q' -> KeyEvent.KEYCODE_Q
            'r' -> KeyEvent.KEYCODE_R
            's' -> KeyEvent.KEYCODE_S
            't' -> KeyEvent.KEYCODE_T
            'u' -> KeyEvent.KEYCODE_U
            'v' -> KeyEvent.KEYCODE_V
            'w' -> KeyEvent.KEYCODE_W
            'x' -> KeyEvent.KEYCODE_X
            'y' -> KeyEvent.KEYCODE_Y
            'z' -> KeyEvent.KEYCODE_Z
            '0', ')' -> KeyEvent.KEYCODE_0
            '1', '!' -> KeyEvent.KEYCODE_1
            '2', '@' -> KeyEvent.KEYCODE_2
            '3', '#' -> KeyEvent.KEYCODE_3
            '4', '$' -> KeyEvent.KEYCODE_4
            '5', '%' -> KeyEvent.KEYCODE_5
            '6', '^' -> KeyEvent.KEYCODE_6
            '7', '&' -> KeyEvent.KEYCODE_7
            '8', '*' -> KeyEvent.KEYCODE_8
            '9', '(' -> KeyEvent.KEYCODE_9
            ' ' -> KeyEvent.KEYCODE_SPACE
            '\n' -> KeyEvent.KEYCODE_ENTER
            '\t' -> KeyEvent.KEYCODE_TAB
            '-', '_' -> KeyEvent.KEYCODE_MINUS
            '=', '+' -> KeyEvent.KEYCODE_EQUALS
            '[', '{' -> KeyEvent.KEYCODE_LEFT_BRACKET
            ']', '}' -> KeyEvent.KEYCODE_RIGHT_BRACKET
            '\\', '|' -> KeyEvent.KEYCODE_BACKSLASH
            ';', ':' -> KeyEvent.KEYCODE_SEMICOLON
            '\'', '"' -> KeyEvent.KEYCODE_APOSTROPHE
            ',', '<' -> KeyEvent.KEYCODE_COMMA
            '.', '>' -> KeyEvent.KEYCODE_PERIOD
            '/', '?' -> KeyEvent.KEYCODE_SLASH
            '`', '~' -> KeyEvent.KEYCODE_GRAVE
            else -> null
        } ?: return null

        val requiresShift = isUppercaseLetter || char in SHIFTED_SYMBOLS

        return KeyDispatch(keyCode = keyCode, requiresShift = requiresShift)
    }

    fun showKeyboard() = showKeyboard(null)

    fun showKeyboard(chatSend: (() -> Unit)?) {
        post {
            if (!isAttachedToWindow) return@post
            imeSessionActive = true
            onChatSend = chatSend
            isFocusable = true
            isFocusableInTouchMode = true
            if (!requestFocus()) return@post
            val imm = displayContext.getSystemService(InputMethodManager::class.java)
            imm?.restartInput(this)
            if (imm?.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT) != true) {
                ViewCompat.getWindowInsetsController(this)?.show(WindowInsetsCompat.Type.ime())
            }
        }
    }

    fun hideKeyboard() {
        post {
            val imm = displayContext.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(windowToken, 0)
            imeSessionActive = false
            onChatSend = null
            clearFocus()
            isFocusable = false
            isFocusableInTouchMode = false
            Timber.d("IMEInputReceiver: Requested to hide keyboard")
        }
    }
}

// Wine's current keyboard bridge sends US keyboard events. Only chat may substitute characters.
internal fun normalizeMobileChat(text: CharSequence): String = buildString(text.length) {
    for (character in text) {
        append(when (character) {
            'ä' -> "ae"
            'ö' -> "oe"
            'ü' -> "ue"
            'Ä' -> "Ae"
            'Ö' -> "Oe"
            'Ü' -> "Ue"
            'ß' -> "ss"
            'ẞ' -> "SS"
            '\n', '\r', '\t', '\u00a0' -> " "
            '‘', '’' -> "'"
            '“', '”', '„' -> "\""
            '–', '—' -> "-"
            '…' -> "..."
            else -> character.toString()
        })
    }
}
