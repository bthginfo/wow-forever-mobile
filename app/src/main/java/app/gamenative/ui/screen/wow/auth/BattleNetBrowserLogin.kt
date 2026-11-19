package app.gamenative.ui.screen.wow.auth

import android.content.Context
import android.content.res.Resources
import androidx.annotation.StringRes
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.gamenative.BuildConfig
import app.gamenative.PluviaApp
import app.gamenative.R
import app.gamenative.events.AndroidEvent
import app.gamenative.ui.screen.wow.GameRegion
import app.gamenative.ui.screen.wow.MobileLaunchDiagnostics
import app.gamenative.ui.screen.wow.WowClientDownloader
import app.gamenative.ui.util.SnackbarManager
import com.winlator.container.Container
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference

/** Browser authentication. Tokens never enter game files, arguments, preferences, or logs. */
internal object BattleNetBrowserLogin {
    private const val ASSET = "wow-session-bridge.exe"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutableUi = MutableStateFlow<Ui>(Ui.Idle)
    val ui = mutableUi.asStateFlow()
    private var active: Attempt? = null

    sealed interface Ui {
        data object Idle : Ui
        class Waiting(@StringRes val label: Int) : Ui
        // Deliberately no generated toString: a challenge URL is sensitive.
        class Browser(val url: String) : Ui {
            val page = BattleNetWebPage(
                url,
                onTicket = { BattleNetBrowserLogin.submit(this, it) },
                onError = { BattleNetBrowserLogin.webError(this, it) },
            )
        }
        class Failed(val text: String) : Ui
    }

    /** Runs after Wine prefix initialization. Container executable remains the game for window tracking. */
    @Synchronized
    fun start(context: Context, container: Container): String {
        cancel()
        val gamePath = container.executablePath
        check(' ' !in gamePath) { "The game path can't contain spaces for browser login" }
        val gameRoot = Container.drivesIterator(container.drives).asSequence()
            .firstOrNull { it[0].equals("G", ignoreCase = true) }?.let { File(it[1]) }
            ?: throw IOException("Cannot locate the game drive for browser login")
        val build = WowClientDownloader.readBuildInfo(File(gameRoot, WowClientDownloader.BUILD_INFO))
            ?.get("Version")?.substringAfterLast('.')?.toIntOrNull()?.takeIf { it > 0 }
            ?: throw IOException("Cannot read the installed game build for browser login")
        val region = GameRegion.current(context, gameRoot.path)
        // An older launcher may have left a password file or an AtomicFile journal in shared storage.
        for (flavor in listOf(WowClientDownloader.FLAVOR_DIR, WowClientDownloader.LEGACY_FLAVOR_DIR)) {
            val directory = File(gameRoot, flavor)
            for (name in listOf("login.txt", "login.txt.new", "login.txt.bak")) {
                val file = File(directory, name)
                if (file.isFile) file.delete()
            }
        }
        check(!File(gameRoot, "${WowClientDownloader.FLAVOR_DIR}/login.txt").exists()) {
            context.getString(R.string.mobile_browser_error_legacy_file)
        }

        val directory = File(container.rootDir, ".wine/drive_c/wow-session")
        check(directory.isDirectory || directory.mkdirs()) { "Cannot prepare browser login" }
        // The prefix is in Android's app-private directory, never shared game storage.
        val helper = File(directory, ASSET)
        context.assets.open(ASSET).use { input -> helper.outputStream().use { input.copyTo(it) } }
        val bridge = SessionBridge()
        val request = File(directory, "request-${UUID.randomUUID()}.txt")
        try {
            request.writeText(bridge.config, Charsets.US_ASCII)
            request.setReadable(false, false)
            request.setWritable(false, false)
            check(request.setReadable(true, true) && request.setWritable(true, true)) {
                "Cannot protect the browser login request"
            }
            val log = File(gameRoot, "${WowClientDownloader.FLAVOR_DIR}/Logs/BrowserLogin.log")
            val attempt = Attempt(bridge, request, "${region.name}.actual.battle.net", build, log, context.resources)
            diag(attempt, "browser login started (app ${BuildConfig.VERSION_NAME}, ${region.name}, build $build)")
            active = attempt
            val starting = R.string.mobile_browser_starting
            publish(attempt, Ui.Waiting(starting), starting)
            // One deadline covers Wine startup, queues and browser interaction, below the helper's 15 minutes.
            attempt.watchdog = scope.launch {
                delay(10 * 60_000L)
                fail(attempt, attempt.resources.getString(R.string.mobile_browser_error_timeout))
            }
            attempt.job = scope.launch { run(attempt) }
            // These arguments contain paths and public switches only. The token travels over the authenticated socket.
            // No quotes: ProcessHelper.splitCommand keeps quote characters, so Wine would get them as part of each
            // path and couldn't find the helper. None of these paths contain spaces.
            val checkArgument = if (BuildConfig.PIXEL_VULKAN_TEST) " --check-d3d11" else ""
            return "C:\\wow-session\\$ASSET C:\\wow-session\\${request.name} " +
                "$gamePath -launcherlogin -uid ${WowClientDownloader.TARGET_PRODUCT} -d3d11$checkArgument"
        } catch (error: Exception) {
            bridge.close()
            request.delete()
            throw error
        }
    }

    private suspend fun run(attempt: Attempt) {
        try {
            diag(attempt, "waiting for the helper to connect")
            attempt.bridge.accept().use { peer ->
                diag(attempt, "helper connected")
                if (BuildConfig.PIXEL_VULKAN_TEST) {
                    val checking = R.string.mobile_graphics_check_starting
                    publish(attempt, Ui.Waiting(checking), checking)
                    if (!acceptGraphicsResult(attempt, peer.graphicsResult())) return
                }
                val device = peer.device().also { attempt.device.set(it) }
                validateDevice(device)
                val url = withClient(attempt) { client ->
                    client.connect()
                    client.webChallenge(device, attempt.build)
                }
                diag(attempt, "showing the Battle.net sign-in page")
                publish(attempt, Ui.Browser(url), R.string.mobile_browser_page)
                val ticket = withTimeout(15 * 60_000L) { attempt.ticket.await() }
                diag(attempt, "sign-in page finished")
                try {
                    val verifying = R.string.mobile_browser_verifying
                    publish(attempt, Ui.Waiting(verifying), verifying)
                    // A fresh connection avoids holding a BGS socket open while the user handles CAPTCHA or 2FA.
                    val token = withClient(attempt) { client ->
                        client.connect()
                        client.webChallenge(device, attempt.build)
                        client.verifyAndGenerateGameToken(ticket)
                    }
                    try {
                        diag(attempt, "Battle.net issued a game session; handing it to the helper")
                        val launching = R.string.mobile_browser_launching
                        publish(attempt, Ui.Waiting(launching), launching)
                        peer.launch(token)
                    } finally {
                        token.fill(0)
                    }
                } finally {
                    ticket.fill(0)
                    device.fill(0)
                }
                diag(attempt, "the game started with the Battle.net session")
                publish(attempt, Ui.Idle, R.string.mobile_browser_handed_off)
            }
        } catch (_: TimeoutCancellationException) {
            fail(attempt, attempt.resources.getString(R.string.mobile_browser_error_timeout))
        } catch (_: CancellationException) {
            // User cancellation does not turn into a password-login attempt.
        } catch (error: BgsException) {
            diag(attempt, "Battle.net error: ${error.message}")
            fail(attempt, error.message ?: attempt.resources.getString(R.string.mobile_browser_failed))
        } catch (error: Exception) {
            // The exception type only: messages can carry provider payloads or addresses.
            diag(attempt, "stopped: ${error.javaClass.simpleName}")
            // Never expose provider payloads, redirect URLs, credentials or arbitrary peer output.
            fail(attempt, attempt.resources.getString(R.string.mobile_browser_error_launch))
        } finally {
            attempt.close()
            synchronized(this) { if (active === attempt) active = null }
        }
    }

    @Synchronized
    private fun acceptGraphicsResult(attempt: Attempt, code: String): Boolean {
        if (active !== attempt || attempt.cancelled) return false
        MobileLaunchDiagnostics.graphicsChecked(code)
        if (code == "00000000") return true
        fail(attempt, attempt.resources.getString(R.string.mobile_graphics_check_failed, code))
        return false
    }

    private fun <T> withClient(attempt: Attempt, action: (BgsClient) -> T): T {
        // The ARM64 helper reports the real Windows-on-ARM context, the same platform as the ARM64 game client.
        val client = BgsClient(attempt.host, platform = "WinA")
        attempt.client.set(client)
        try {
            if (attempt.cancelled) throw CancellationException()
            return action(client)
        } finally {
            attempt.client.compareAndSet(client, null)
            client.close()
        }
    }

    private fun validateDevice(device: ByteArray) {
        val expected = setOf("RGKY", "CPGE", "ULNG", "SLNG", "CNME", "UNME", "UTCO", "CARC", "CREV", "CLVL",
            "PMEM", "PSZE", "OVER", "CVRA", "CFTC", "CFTD", "CEFC", "CEFD", "CBRD", "CVEN", "ANME", "ADSC", "MAC")
        val json = JSONObject(device.toString(Charsets.UTF_8))
        check(json.keys().asSequence().toSet() == expected) { "Invalid device description" }
        expected.forEach { check(json.getLong(it) in 0..0xffff_ffffL) { "Invalid device description" } }
    }

    /** Appends a step to the game folder's BrowserLogin.log for device testing. Never pass credentials or URLs. */
    private fun diag(attempt: Attempt, message: String) {
        runCatching {
            attempt.log.parentFile?.mkdirs()
            val time = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())
            attempt.log.appendText("$time app: $message\n")
        }
    }

    @Synchronized
    private fun publish(attempt: Attempt, state: Ui, @StringRes step: Int) {
        if (active !== attempt || attempt.cancelled) return
        MobileLaunchDiagnostics.browserStep(step)
        updateUi(state)
    }

    // All callers hold the coordinator lock. Only switching attempts or completing one releases the page.
    private fun updateUi(state: Ui) {
        val previous = mutableUi.value
        if (previous === state) return
        mutableUi.value = state
        (previous as? Ui.Browser)?.page?.close()
    }

    @Synchronized
    fun submit(browser: Ui.Browser, ticket: ByteArray) {
        val attempt = active
        if (mutableUi.value !== browser || attempt == null || attempt.ticket.isCompleted) {
            ticket.fill(0)
        } else {
            attempt.ticketBytes.set(ticket)
            attempt.ticket.complete(ticket)
        }
    }

    @Synchronized
    fun cancel(preserveFailure: Boolean = false) {
        active?.let { attempt ->
            if (mutableUi.value !is Ui.Failed && mutableUi.value !is Ui.Idle) {
                MobileLaunchDiagnostics.browserStep(R.string.mobile_browser_cancelled)
            }
            attempt.cancelled = true
            attempt.close()
            attempt.job?.cancel()
        }
        active = null
        if (!preserveFailure || mutableUi.value !is Ui.Failed) updateUi(Ui.Idle)
    }

    @Synchronized
    fun abort(state: Ui) {
        if (mutableUi.value !== state) return
        cancel()
        // Closing the control socket alone cannot stop a helper that has already received the token.
        if (state !is Ui.Failed) PluviaApp.events.emit(AndroidEvent.ForceCloseApp)
    }

    @Synchronized
    fun webError(browser: Ui.Browser, message: String) {
        if (mutableUi.value === browser) active?.let { fail(it, message) }
    }

    @Synchronized
    private fun fail(attempt: Attempt, message: String) {
        if (active !== attempt || attempt.cancelled || mutableUi.value is Ui.Idle) return
        val failure = Ui.Failed(message)
        publish(attempt, failure, R.string.mobile_browser_failed)
        cancel(preserveFailure = true)
        scope.launch(Dispatchers.Main.immediate) {
            synchronized(this@BattleNetBrowserLogin) {
                // A queued failure must not tear down a newer attempt or a game the user has since launched.
                if (mutableUi.value === failure) PluviaApp.events.emit(AndroidEvent.ForceCloseApp)
            }
        }
    }

    @Synchronized
    fun guestExited(): Boolean {
        val attempt = active
        val failedBeforeSignIn = attempt != null && mutableUi.value !is Ui.Idle && mutableUi.value !is Ui.Failed
        if (attempt != null && failedBeforeSignIn) {
            diag(attempt, "the Wine side exited before sign-in completed")
            publish(
                attempt,
                Ui.Failed(attempt.resources.getString(R.string.mobile_browser_error_wine, "_forever_/Logs/BrowserLogin.log")),
                R.string.mobile_browser_failed,
            )
        }
        val hasFailure = mutableUi.value is Ui.Failed
        cancel(preserveFailure = true)
        return hasFailure
    }

    private class Attempt(
        val bridge: SessionBridge,
        val request: File,
        val host: String,
        val build: Int,
        val log: File,
        val resources: Resources,
    ) {
        val ticket = CompletableDeferred<ByteArray>()
        val client = AtomicReference<BgsClient?>()
        val ticketBytes = AtomicReference<ByteArray?>()
        val device = AtomicReference<ByteArray?>()
        @Volatile var cancelled = false
        var job: Job? = null
        var watchdog: Job? = null
        fun close() {
            runCatching { client.getAndSet(null)?.close() }
            runCatching { bridge.close() }
            watchdog?.cancel()
            ticketBytes.getAndSet(null)?.fill(0)
            device.getAndSet(null)?.fill(0)
            request.delete()
        }
    }
}

@Composable
internal fun BattleNetBrowserLoginHost(launcherVisible: Boolean) {
    val state by BattleNetBrowserLogin.ui.collectAsStateWithLifecycle()
    when (val current = state) {
        BattleNetBrowserLogin.Ui.Idle -> Unit
        is BattleNetBrowserLogin.Ui.Browser -> BattleNetWebDialog(current)
        is BattleNetBrowserLogin.Ui.Failed -> if (launcherVisible) {
            LaunchedEffect(current) {
                if (BattleNetBrowserLogin.ui.value === current) {
                    BattleNetBrowserLogin.abort(current)
                    SnackbarManager.show(current.text)
                }
            }
        }
        is BattleNetBrowserLogin.Ui.Waiting -> AlertDialog(
            onDismissRequest = { BattleNetBrowserLogin.abort(current) },
            properties = DialogProperties(
                dismissOnBackPress = false,
                dismissOnClickOutside = false,
            ),
            title = { Text(stringResource(R.string.mobile_browser_login)) },
            text = { Text(stringResource(current.label)) },
            confirmButton = {
                TextButton(onClick = { BattleNetBrowserLogin.abort(current) }) {
                    Text(stringResource(android.R.string.cancel))
                }
            },
        )
    }
}
