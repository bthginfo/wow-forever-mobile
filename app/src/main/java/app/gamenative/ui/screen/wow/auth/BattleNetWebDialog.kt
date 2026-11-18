package app.gamenative.ui.screen.wow.auth

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.SecureFlagPolicy
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.gamenative.GameSessionService
import app.gamenative.R
import app.gamenative.ui.screen.wow.openBattleNetApp
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicBoolean
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
        Surface(modifier = Modifier.fillMaxSize()) {
            Column {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(page.origin, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
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
                                        authenticatorUnavailable = !openBattleNetApp(context, notifyIfUnavailable = false)
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

    var origin by mutableStateOf(BrowserAuthUrl.displayOrigin(url) ?: "Battle.net")
        private set

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
    private fun createWebView(context: Context) = WebView(MutableContextWrapper(context)).apply {
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
