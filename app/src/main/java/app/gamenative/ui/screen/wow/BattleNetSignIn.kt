package app.gamenative.ui.screen.wow

import android.content.Context
import android.os.FileObserver
import android.os.SystemClock
import android.util.AtomicFile
import android.util.Base64
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.gamenative.Crypto
import app.gamenative.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import timber.log.Timber
import java.io.File
import java.util.concurrent.atomic.AtomicLong

object BattleNetSignIn {
    data class Login(val email: String, val password: String) {
        val canWriteLoginFile: Boolean
            get() = email.isNotBlank() && password.isNotEmpty() &&
                email.none(::isLoginFileSeparator) && password.none(::isLoginFileSeparator)
    }

    fun load(context: Context): Login? {
        val prefs = prefs(context)
        val email = prefs.getString(KEY_EMAIL, null) ?: return null
        val sealed = prefs.getString(KEY_PASSWORD, null) ?: return null
        return try {
            Login(email, String(Crypto.decrypt(Base64.decode(sealed, Base64.NO_WRAP))))
        } catch (e: Exception) {
            Timber.w(e, "Saved Battle.net login unreadable, clearing it")
            forget(context)
            null
        }
    }

    fun save(context: Context, login: Login) {
        require(login.canWriteLoginFile) { "Login fields must fit on one line each." }
        val sealed = Base64.encodeToString(Crypto.encrypt(login.password.toByteArray()), Base64.NO_WRAP)
        prefs(context).edit().putString(KEY_EMAIL, login.email).putString(KEY_PASSWORD, sealed).apply()
    }

    fun forget(context: Context) {
        prefs(context).edit().clear().apply()
    }

    private var watcher: Job? = null
    private var watchedRoot: File? = null
    private var generation = 0L

    @Synchronized
    fun prepareLoginFile(gameRoot: File, login: Login): Boolean {
        removeLoginFile(gameRoot)
        if (!login.canWriteLoginFile) return false
        val flavorDir = File(gameRoot, WowClientDownloader.FLAVOR_DIR)
        val file = File(flavorDir, LOGIN_FILE)
        try {
            flavorDir.mkdirs()
            val payload = "${login.email}\n${login.password}\n".toByteArray(Charsets.UTF_8)
            val atomicFile = AtomicFile(file)
            val output = atomicFile.startWrite()
            try {
                output.write(payload)
                atomicFile.finishWrite(output)
            } catch (error: Exception) {
                atomicFile.failWrite(output)
                throw error
            } finally {
                payload.fill(0)
            }
            check(file.isFile && file.length() > 0L) { "The login file was not available after writing." }
        } catch (e: Exception) {
            eraseLoginFiles(gameRoot)
            Timber.e(e, "Failed to write login.txt")
            return false
        }

        val attempt = generation
        val started = SystemClock.elapsedRealtime()
        val hotfixLog = File(flavorDir, "Logs/Hotfix.log")
        val initialLogLength = hotfixLog.length()
        val initialLogTimestamp = hotfixLog.lastModified()
        val lastRead = AtomicLong(-1L)
        watchedRoot = gameRoot
        watcher = CoroutineScope(Dispatchers.IO).launch {
            @Suppress("DEPRECATION") // The File constructor needs API 29.
            val observer = object : FileObserver(flavorDir.path, CLOSE_NOWRITE) {
                override fun onEvent(event: Int, path: String?) {
                    if (path == LOGIN_FILE) lastRead.set(SystemClock.elapsedRealtime())
                }
            }
            try {
                observer.startWatching()
                while (isActive && SystemClock.elapsedRealtime() - started < 600_000L) {
                    val hasNewHotfixData = hotfixLog.lastModified() != initialLogTimestamp &&
                        (hotfixLog.length() - initialLogLength > 50_000L ||
                            (hotfixLog.length() < initialLogLength && hotfixLog.length() > 50_000L))
                    val lastAccess = lastRead.get()
                    if (hasNewHotfixData || (lastAccess >= 0 && SystemClock.elapsedRealtime() - lastAccess > 60_000L)) break
                    delay(1000L)
                }
            } finally {
                observer.stopWatching()
                finishLoginAttempt(gameRoot, attempt)
            }
        }
        return true
    }

    @Synchronized
    private fun finishLoginAttempt(gameRoot: File, attempt: Long) {
        if (generation != attempt) return
        watcher = null
        watchedRoot = null
        eraseLoginFiles(gameRoot)
    }

    @Synchronized
    fun removeLoginFile(gameRoot: File) {
        generation++
        watcher?.cancel()
        watcher = null
        watchedRoot?.takeIf { it != gameRoot }?.let(::eraseLoginFiles)
        watchedRoot = null
        eraseLoginFiles(gameRoot)
    }

    // Also clears a login.txt from the earlier beta directory.
    private fun eraseLoginFiles(gameRoot: File) {
        listOf(WowClientDownloader.FLAVOR_DIR, WowClientDownloader.LEGACY_FLAVOR_DIR).forEach { flavorDir ->
            listOf(LOGIN_FILE, "$LOGIN_FILE.new", "$LOGIN_FILE.bak").forEach { name ->
                try {
                    val file = File(File(gameRoot, flavorDir), name)
                    if (file.isFile) {
                        file.writeBytes(ByteArray(file.length().coerceAtMost(4096).toInt()))
                        file.delete()
                    }
                } catch (e: Exception) {
                    Timber.e(e, "Failed to remove a temporary login file")
                }
            }
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private const val PREFS = "battle_net_login"
    private const val KEY_EMAIL = "email"
    private const val KEY_PASSWORD = "password"
    private const val LOGIN_FILE = "login.txt"

    private fun isLoginFileSeparator(character: Char) = character == '\r' || character == '\n' || character == '\u0000'
}

@Composable
fun BattleNetCredentialDialog(
    onDismiss: () -> Unit,
    onConfirm: (BattleNetSignIn.Login) -> Unit,
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    val emailFocus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val login = BattleNetSignIn.Login(email.trim(), password)
    LaunchedEffect(Unit) {
        delay(DIALOG_SETTLE_MS)
        emailFocus.requestFocus()
        keyboard?.show()
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.mobile_saved_login_title)) },
        text = {
            Column {
                Text(stringResource(R.string.mobile_saved_login_details))
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text(stringResource(R.string.mobile_login_email)) },
                    singleLine = true,
                    modifier = Modifier.focusRequester(emailFocus),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text(stringResource(R.string.mobile_login_password)) },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = login.canWriteLoginFile,
                onClick = { onConfirm(login) },
            ) { Text(stringResource(R.string.save)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

private const val DIALOG_SETTLE_MS = 300L
