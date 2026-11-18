package app.gamenative.ui.screen.wow

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.SystemClock
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.gamenative.BuildConfig
import app.gamenative.R
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal object MobileLaunchDiagnostics {
    private data class BrowserStep(@StringRes val label: Int, val elapsedMs: Long)

    private data class Launch(
        val log: File,
        val initialLength: Long,
        val startTime: Long,
        val startElapsed: Long,
        val region: GameRegion,
        val network: ConnectionSnapshot,
        val runtime: Long? = null,
        val container: Long? = null,
        val frame: Long? = null,
        val loginMethod: Int? = null,
        val browserStep: BrowserStep? = null,
        val battleNetAppOpened: Boolean = false,
        val guestExit: GuestExit? = null,
    )

    private data class CachedLogin(val launchTime: Long, val length: Long, val modified: Long, val state: LoginState)

    @Volatile
    private var lastLaunch: Launch? = null
    @Volatile
    private var cachedLogin: CachedLogin? = null

    @Synchronized
    fun start(context: Context, gameRoot: File, region: GameRegion) {
        val log = File(gameRoot, "${WowClientDownloader.FLAVOR_DIR}/Logs/Connection.log")
        lastLaunch = Launch(log, log.length(), System.currentTimeMillis(), SystemClock.elapsedRealtime(), region, currentNetwork(context))
        cachedLogin = null
    }

    @Synchronized
    fun runtimeReady() {
        val launch = lastLaunch ?: return
        lastLaunch = launch.copy(runtime = SystemClock.elapsedRealtime() - launch.startElapsed)
    }

    @Synchronized
    fun containerReady() {
        val launch = lastLaunch ?: return
        lastLaunch = launch.copy(container = SystemClock.elapsedRealtime() - launch.startElapsed)
    }

    @Synchronized
    fun firstWindowContent() {
        val launch = lastLaunch ?: return
        if (launch.frame == null) lastLaunch = launch.copy(frame = SystemClock.elapsedRealtime() - launch.startElapsed)
    }

    @Synchronized
    fun loginMethod(label: Int) {
        val launch = lastLaunch ?: return
        lastLaunch = launch.copy(loginMethod = label)
    }

    @Synchronized
    fun browserStep(@StringRes label: Int) {
        val launch = lastLaunch ?: return
        lastLaunch = launch.copy(browserStep = BrowserStep(label, SystemClock.elapsedRealtime() - launch.startElapsed))
    }

    @Synchronized
    fun battleNetAppOpened() {
        val launch = lastLaunch ?: return
        lastLaunch = launch.copy(battleNetAppOpened = true)
    }

    @Synchronized
    fun guestExited(status: Int, visible: Boolean, foregroundService: Boolean) {
        val launch = lastLaunch ?: return
        lastLaunch = launch.copy(guestExit = GuestExit(status, visible, foregroundService))
    }

    fun summary(): LaunchReport? {
        val launch = lastLaunch ?: return null
        val connection = readConnection(launch)
        return LaunchReport(
            listOf(launch.runtime, launch.container, launch.frame), connection.state,
            launch.region, launch.network, launch.loginMethod, launch.battleNetAppOpened, launch.guestExit,
            launch.browserStep?.label, connection.browserStalled,
        )
    }

    fun connection(): LoginObservation? = lastLaunch?.let(::readConnection)

    private fun readConnection(launch: Launch): LoginObservation {
        val state = readLogin(launch)
        val handoffMs = launch.browserStep?.takeIf { it.label == R.string.mobile_browser_handed_off }?.elapsedMs
        val stalled = launch.guestExit == null && browserConnectionStalled(
            state, SystemClock.elapsedRealtime() - launch.startElapsed, launch.frame, handoffMs,
        )
        return LoginObservation(state, stalled)
    }

    private fun readLogin(launch: Launch): LoginState {
        val modified = launch.log.lastModified()
        if (modified < launch.startTime) return LoginState(R.string.mobile_diagnostics_no_connection)
        val fileLength = launch.log.length()
        cachedLogin?.let { cached ->
            if (cached.launchTime == launch.startElapsed && cached.length == fileLength && cached.modified == modified) {
                return cached.state
            }
        }
        return runCatching {
            RandomAccessFile(launch.log, "r").use { file ->
                val length = file.length()
                val offset = if (length < launch.initialLength) 0 else launch.initialLength
                val begin = maxOf(offset, length - (32 * 1024))
                file.seek(begin)
                val recentLog = ByteArray((length - begin).toInt()).also(file::readFully).toString(Charsets.UTF_8)
                readLoginState(recentLog).also { state ->
                    cachedLogin = CachedLogin(launch.startElapsed, length, modified, state)
                }
            }
        }.getOrDefault(LoginState(R.string.mobile_diagnostics_no_connection))
    }
}

internal data class ConnectionSnapshot(val network: Network?, val label: Int)

internal data class GuestExit(val status: Int, val visible: Boolean, val foregroundService: Boolean)

internal data class LoginObservation(val state: LoginState, val browserStalled: Boolean)

internal data class LaunchReport(
    val timings: List<Long?>,
    val login: LoginState,
    val region: GameRegion,
    val startNetwork: ConnectionSnapshot,
    val loginMethod: Int?,
    val battleNetAppOpened: Boolean,
    val guestExit: GuestExit?,
    @StringRes val browserStep: Int?,
    val browserStalled: Boolean,
)

private fun currentNetwork(context: Context): ConnectionSnapshot {
    val manager = context.getSystemService(ConnectivityManager::class.java)
    val network = manager?.activeNetwork ?: return ConnectionSnapshot(null, R.string.mobile_network_unavailable)
    val caps = manager.getNetworkCapabilities(network)
    val label = when {
        caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true -> R.string.mobile_network_vpn
        caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> R.string.mobile_network_wifi
        caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> R.string.mobile_network_cellular
        else -> R.string.mobile_network_other
    }
    return ConnectionSnapshot(network, label)
}

internal data class LoginState(
    val phase: Int,
    val code: String? = null,
    val failedAfter: Int? = null,
    val timestamp: String? = null,
    val authenticatorRequired: Boolean? = null,
) {
    val showsLoginControls: Boolean
        get() = phase == R.string.mobile_diagnostics_error || phase == R.string.mobile_diagnostics_authenticator

    val waitingForConnection: Boolean
        get() = phase == R.string.mobile_diagnostics_no_connection || phase == R.string.mobile_diagnostics_connecting
}

// The upstream report associates a long-running Android boot with a blank login around this 32-bit timer limit (#36).
internal fun mightHaveWrappedLoginTimer(elapsedSinceBootMs: Long): Boolean = elapsedSinceBootMs >= 4_294_967_296L

internal fun browserConnectionStalled(state: LoginState, elapsedMs: Long, frameMs: Long?, handoffMs: Long?): Boolean {
    if (frameMs == null || handoffMs == null) return false
    return state.waitingForConnection && elapsedMs - maxOf(frameMs, handoffMs) >= 35_000L
}

private val blizzardCode = Regex("\\bBLZ[0-9]{8}\\b")
private val logTimestamp = Regex("^\\d{1,2}/\\d{1,2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}")

private fun authenticatorFlag(line: String): Boolean? =
    line.substringAfter("authenticatorRequired=\"", "").substringBefore('"').toBooleanStrictOrNull()

/** Returns only fixed status labels and validated error codes. Raw log lines can contain account data. */
internal fun readLoginState(log: String): LoginState {
    var state = LoginState(R.string.mobile_diagnostics_no_connection)
    for (line in log.lineSequence()) {
        when {
            "Opened for Append" in line -> state = LoginState(R.string.mobile_diagnostics_no_connection)
            "Battle.net logon requested" in line -> state = LoginState(R.string.mobile_diagnostics_connecting)
            "Battle.net authentication server connected" in line || "Battle.net front connected" in line ->
                state = LoginState(R.string.mobile_diagnostics_connected)
            "Battle.net external challenge received" in line ->
                state = LoginState(R.string.mobile_diagnostics_challenge)
            "Battle.net SRP endpoint response received" in line ->
                state = LoginState(R.string.mobile_diagnostics_srp)
            "Battle.net logon form submission response" in line -> {
                val required = authenticatorFlag(line)
                val phase = if (required == true) R.string.mobile_diagnostics_authenticator else R.string.mobile_diagnostics_form_response
                state = LoginState(phase, authenticatorRequired = required)
            }
            "Fatal login error received" in line -> {
                val code = blizzardCode.find(line)?.value ?: if ("(14400)" in line) "BLZ51914400" else null
                val lastStep = if (state.phase == R.string.mobile_diagnostics_error) state.failedAfter else state.phase
                state = LoginState(
                    R.string.mobile_diagnostics_error, code ?: state.code, lastStep, logTimestamp.find(line)?.value,
                    authenticatorRequired = authenticatorFlag(line) ?: state.authenticatorRequired,
                )
            }
        }
    }
    return state
}

@Composable
internal fun MobileDiagnosticsDialog(onRetryBrowserLogin: (() -> Unit)? = null, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var report by remember { mutableStateOf("") }
    var retryAvailable by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        val data = withContext(Dispatchers.IO) { MobileLaunchDiagnostics.summary() }
        val uptime = SystemClock.elapsedRealtime()
        report = formatDiagnostics(context, uptime, data)
        retryAvailable = data?.browserStalled == true
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.mobile_diagnostics)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(report.ifEmpty { "…" })
                if (retryAvailable && onRetryBrowserLogin != null) {
                    TextButton(onClick = {
                        onDismiss()
                        onRetryBrowserLogin()
                    }) { Text(stringResource(R.string.mobile_retry_browser_login)) }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(android.R.string.ok)) }
        },
        dismissButton = {
            TextButton(
                enabled = report.isNotEmpty(),
                onClick = {
                    context.getSystemService(ClipboardManager::class.java)
                        ?.setPrimaryClip(ClipData.newPlainText("WoW Forever Mobile", report))
                    onDismiss()
                },
            ) { Text(stringResource(R.string.mobile_copy_diagnostics)) }
        },
    )
}

private fun formatDiagnostics(context: Context, elapsedSinceBoot: Long, data: LaunchReport?): String = buildString {
    appendLine("WoW Forever Mobile ${BuildConfig.VERSION_NAME}")
    val days = TimeUnit.MILLISECONDS.toDays(elapsedSinceBoot)
    val hours = TimeUnit.MILLISECONDS.toHours(elapsedSinceBoot) % 24
    appendLine(context.getString(R.string.mobile_device_uptime, days, hours))
    appendLine()
    if (data == null) {
        append(context.getString(R.string.mobile_diagnostics_no_attempt))
    } else {
        val (timings, state) = data
        appendLine(context.getString(R.string.mobile_diagnostics_region, context.getString(data.region.label)))
        data.loginMethod?.let { appendLine(context.getString(it)) }
        data.browserStep?.let { appendLine(context.getString(R.string.mobile_diagnostics_browser_step, context.getString(it))) }
        val network = currentNetwork(context)
        appendLine(context.getString(R.string.mobile_network_at_launch, context.getString(data.startNetwork.label)))
        if (network != data.startNetwork) {
            appendLine(context.getString(R.string.mobile_network_changed, context.getString(network.label)))
        }
        val phases = listOf(R.string.mobile_runtime, R.string.mobile_container, R.string.mobile_window)
        timings.forEachIndexed { index, ms ->
            if (ms != null) appendLine(context.getString(R.string.mobile_timing, context.getString(phases[index]), ms / 1000.0))
        }
        append(context.getString(state.phase))
        state.code?.let { append(" ($it)") }
        if (data.browserStalled) {
            appendLine()
            append(context.getString(R.string.mobile_diagnostics_stalled))
        }
        state.failedAfter?.let { lastStep ->
            appendLine()
            append(context.getString(R.string.mobile_diagnostics_last_step, context.getString(lastStep)))
        }
        state.authenticatorRequired?.let { required ->
            appendLine()
            append(context.getString(if (required) R.string.mobile_auth_requested else R.string.mobile_auth_not_requested))
        }
        if (data.battleNetAppOpened) {
            appendLine()
            append(context.getString(R.string.mobile_battle_net_opened))
        }
        data.guestExit?.let { exit ->
            appendLine()
            appendLine(context.getString(R.string.mobile_game_exit_status, exit.status))
            appendLine(context.getString(if (exit.visible) R.string.mobile_exit_visible else R.string.mobile_exit_background))
            append(context.getString(if (exit.foregroundService) R.string.mobile_service_active else R.string.mobile_service_inactive))
        }
    }
    if (mightHaveWrappedLoginTimer(elapsedSinceBoot) &&
        (data == null || data.login.waitingForConnection)
    ) {
        appendLine()
        appendLine()
        append(context.getString(R.string.mobile_stalled_login_reboot))
    }
}
