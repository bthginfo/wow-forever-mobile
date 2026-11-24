package app.gamenative.ui.screen.wow.auth

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.KeyboardHide
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.window.SecureFlagPolicy
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.gamenative.GameSessionService
import app.gamenative.R
import app.gamenative.ui.component.InlineKey
import app.gamenative.ui.component.InlineKeyboard
import app.gamenative.ui.screen.wow.MobileLaunchDiagnostics
import app.gamenative.ui.screen.wow.openBattleNetApp
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlinx.coroutines.launch

@Composable
internal fun BattleNetWebDialog(browser: BattleNetBrowserLogin.Ui.Browser) {
    val page = browser.page
    val context = LocalContext.current
    if (!BrowserAuthUrl.isInitialUrl(browser.url)) {
        LaunchedEffect(browser) {
            BattleNetBrowserLogin.webError(browser, context.getString(R.string.mobile_browser_error_address))
        }
        return
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val scope = rememberCoroutineScope()
    var switchingApps by remember(browser) { mutableStateOf(false) }
    var authenticatorUnavailable by remember(browser) { mutableStateOf(false) }
    var androidKeyboard by remember(browser) { mutableStateOf(false) }

    LaunchedEffect(browser) {
        GameSessionService.ensureStarted(context.applicationContext)
    }

    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(
            dismissOnBackPress = false,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
            securePolicy = SecureFlagPolicy.SecureOn,
        ),
    ) {
        val view = LocalView.current
        val window = (view.parent as? DialogWindowProvider)?.window
        DisposableEffect(window, androidKeyboard, page) {
            page.setInlineInputEnabled(!androidKeyboard)
            if (!androidKeyboard && window != null) {
                WindowCompat.getInsetsController(window, view).hide(WindowInsetsCompat.Type.ime())
                window.addFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
            }
            onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM) }
        }
        Surface(modifier = Modifier.fillMaxSize()) {
            Column {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(page.origin, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (!androidKeyboard) {
                        IconButton(onClick = { page.showInlineKeyboard(!page.inlineKeyboardVisible) }) {
                            Icon(
                                if (page.inlineKeyboardVisible) Icons.Filled.KeyboardHide else Icons.Filled.Keyboard,
                                stringResource(if (page.inlineKeyboardVisible) R.string.mobile_keyboard_hide else R.string.keyboard),
                            )
                        }
                    }
                    TextButton(onClick = { androidKeyboard = !androidKeyboard }) {
                        Text(stringResource(if (androidKeyboard) R.string.mobile_keyboard_app else R.string.mobile_keyboard_android))
                    }
                    TextButton(
                        enabled = !switchingApps,
                        onClick = {
                            switchingApps = true
                            scope.launch {
                                try {
                                    GameSessionService.prepareForAppSwitch(context)
                                    if (BattleNetBrowserLogin.ui.value === browser &&
                                        lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
                                    ) {
                                        val opened = openBattleNetApp(context, notifyIfUnavailable = false)
                                        authenticatorUnavailable = !opened
                                        if (opened) MobileLaunchDiagnostics.battleNetAppOpened()
                                    }
                                } finally {
                                    switchingApps = false
                                }
                            }
                        },
                    ) { Text(stringResource(R.string.mobile_open_authenticator)) }
                    TextButton(onClick = { BattleNetBrowserLogin.abort(browser) }) {
                        Text(stringResource(android.R.string.cancel))
                    }
                }
                if (authenticatorUnavailable) {
                    Text(
                        stringResource(R.string.mobile_battle_net_unavailable),
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                AndroidView(
                    factory = { viewContext -> FrameLayout(viewContext).also(page::attach) },
                    modifier = Modifier.weight(1f).fillMaxSize(),
                    onRelease = page::detach,
                )
                if (!androidKeyboard && page.inlineKeyboardVisible) {
                    InlineKeyboard(onText = page::insertText, onKey = page::pressKey, showTab = true)
                }
            }
        }
    }
}

/** The active login attempt owns the live page so a new dialog host can reattach it without reloading the form. */
internal class BattleNetWebPage(
    private val url: String,
    private val onTicket: (ByteArray) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val completed = AtomicBoolean(false)
    private var webView: WebView? = null
    @Volatile private var inputGeneration = 0
    private var inlineInputEnabled = true

    var inlineKeyboardVisible by mutableStateOf(false)
        private set

    var origin by mutableStateOf(BrowserAuthUrl.displayOrigin(url) ?: "Battle.net")
        private set

    fun showInlineKeyboard(visible: Boolean) {
        inlineKeyboardVisible = visible && inlineInputEnabled && !completed.get()
    }

    fun setInlineInputEnabled(enabled: Boolean) {
        inlineInputEnabled = enabled
        if (!enabled) {
            inlineKeyboardVisible = false
            inputGeneration++
        }
    }

    fun insertText(text: String) {
        routeInput { commitText(text, 1) }
    }

    fun pressKey(key: InlineKey) {
        if (key == InlineKey.PASTE) {
            routeInput { performContextMenuAction(android.R.id.paste) }
            return
        }
        val code = when (key) {
            InlineKey.BACKSPACE -> KeyEvent.KEYCODE_DEL
            InlineKey.ENTER -> KeyEvent.KEYCODE_ENTER
            InlineKey.TAB -> KeyEvent.KEYCODE_TAB
            InlineKey.LEFT -> KeyEvent.KEYCODE_DPAD_LEFT
            InlineKey.RIGHT -> KeyEvent.KEYCODE_DPAD_RIGHT
            InlineKey.PASTE -> return
        }
        val time = SystemClock.uptimeMillis()
        routeInput {
            sendKeyEvent(inlineWebKeyEvent(time, code, KeyEvent.ACTION_DOWN))
            sendKeyEvent(inlineWebKeyEvent(time, code, KeyEvent.ACTION_UP))
        }
    }

    private fun routeInput(send: InputConnection.() -> Unit) {
        if (completed.get() || !inlineKeyboardVisible) return
        val view = webView ?: return
        val generation = inputGeneration
        dispatchBattleNetInlineInput(view, { inputGeneration == generation && !completed.get() }, send)
    }

    fun attach(host: FrameLayout) {
        if (completed.get() || !BrowserAuthUrl.isInitialUrl(url)) return
        val view = webView ?: createWebView(host.context).also {
            webView = it
            it.loadUrl(url)
        }
        if (view.parent === host) return
        (view.parent as? ViewGroup)?.removeView(view)
        (view.context as MutableContextWrapper).baseContext = host.context
        host.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }

    fun detach(host: FrameLayout) {
        val view = webView ?: return
        if (view.parent !== host) return
        inputGeneration++
        host.removeView(view)
        (view.context as MutableContextWrapper).baseContext = host.context.applicationContext
    }

    fun close() {
        completed.set(true)
        Handler(Looper.getMainLooper()).post(::destroyView)
    }

    private fun destroyView() {
        val view = webView ?: return
        webView = null
        (view.parent as? ViewGroup)?.removeView(view)
        view.destroy()
    }

    @SuppressLint("SetJavaScriptEnabled") // Battle.net's sign-in page requires JavaScript.
    private fun createWebView(context: Context) = InlineEditorWebView(MutableContextWrapper(context)) {
        showInlineKeyboard(true)
    }.apply {
        setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false)
        settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            @Suppress("DEPRECATION")
            allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            allowUniversalAccessFromFileURLs = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setSupportMultipleWindows(false)
            javaScriptCanOpenWindowsAutomatically = false
            cacheMode = WebSettings.LOAD_NO_CACHE
            @Suppress("DEPRECATION")
            saveFormData = false
        }
        webViewClient = object : WebViewClient() {
            private fun fail(view: WebView, message: Int) {
                if (!completed.compareAndSet(false, true)) return
                view.stopLoading()
                onError(view.context.getString(message))
            }

            private fun navigate(view: WebView, address: String): Boolean {
                if (completed.get()) return true
                val ticket = BrowserAuthUrl.ticket(address)
                if (ticket != null) {
                    view.stopLoading()
                    if (completed.compareAndSet(false, true)) onTicket(ticket) else ticket.fill(0)
                    return true
                }
                if (!BrowserAuthUrl.isNavigationUrl(address)) {
                    fail(view, R.string.mobile_browser_error_address)
                    return true
                }
                origin = BrowserAuthUrl.displayOrigin(address) ?: "Battle.net"
                return false
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame) return !request.url.scheme.equals("https", ignoreCase = true)
                return navigate(view, request.url.toString())
            }

            override fun onPageStarted(view: WebView, address: String, favicon: Bitmap?) {
                inputGeneration++
                // Covers main-frame navigations for which WebView skips shouldOverrideUrlLoading (e.g. POST).
                navigate(view, address)
            }

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (request.isForMainFrame && !BrowserAuthUrl.isNavigationUrl(request.url.toString())) {
                    return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
                }
                return null
            }

            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                handler.cancel()
                fail(view, R.string.mobile_browser_error_secure)
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) fail(view, R.string.mobile_browser_error_loading)
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
                if (request.isForMainFrame) fail(view, R.string.mobile_browser_error_response)
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                val message = view.context.getString(R.string.mobile_browser_renderer_stopped)
                destroyView()
                if (completed.compareAndSet(false, true)) onError(message)
                return true
            }
        }
    }
}

internal fun dispatchBattleNetInlineInput(view: WebView, isCurrent: () -> Boolean, send: InputConnection.() -> Unit) {
    if (!view.isAttachedToWindow || !view.hasWindowFocus() || !view.hasFocus() ||
        !view.onCheckIsTextEditor() || !BrowserAuthUrl.isNavigationUrl(view.url.orEmpty())
    ) return
    val connection = view.onCreateInputConnection(EditorInfo()) ?: return
    val action = Runnable { if (isCurrent()) connection.send() }
    val handler = connection.handler
    if (handler != null && handler.looper != Looper.myLooper()) handler.post(action) else action.run()
}

private fun inlineWebKeyEvent(time: Long, keyCode: Int, action: Int): KeyEvent = KeyEvent(
    time, time, action, keyCode, 0, 0, KeyCharacterMap.VIRTUAL_KEYBOARD, 0,
    KeyEvent.FLAG_SOFT_KEYBOARD or KeyEvent.FLAG_KEEP_TOUCH_MODE,
)

private class InlineEditorWebView(context: Context, private val onEditorTap: () -> Unit) : WebView(context) {
    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var startX = 0f
    private var startY = 0f
    private val checkEditor = Runnable { if (hasWindowFocus() && onCheckIsTextEditor()) onEditorTap() }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val result = super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                removeCallbacks(checkEditor)
                startX = event.x
                startY = event.y
            }
            MotionEvent.ACTION_UP -> if (abs(event.x - startX) <= slop && abs(event.y - startY) <= slop) {
                // Chromium reports the new editor after processing the touch in its renderer.
                postDelayed(checkEditor, 100L)
            }
        }
        return result
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(checkEditor)
        super.onDetachedFromWindow()
    }
}
