package app.gamenative.ui.screen.wow

import app.gamenative.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MobileDiagnosticsTest {
    @Test
    fun browserWaitStartsAfterBothTheHandoffAndTheFirstFrame() {
        val noConnection = readLoginState("Client connection initialized")
        assertFalse(browserConnectionStalled(noConnection, 50_000L, frameMs = 4_300L, handoffMs = null))
        assertFalse(browserConnectionStalled(noConnection, 50_000L, frameMs = null, handoffMs = 1_300L))
        assertFalse(browserConnectionStalled(noConnection, 41_499L, frameMs = 4_300L, handoffMs = 6_500L))
        assertTrue(browserConnectionStalled(noConnection, 41_500L, frameMs = 4_300L, handoffMs = 6_500L))
        assertFalse(browserConnectionStalled(noConnection, 39_299L, frameMs = 4_300L, handoffMs = 1_300L))
        assertTrue(browserConnectionStalled(noConnection, 39_300L, frameMs = 4_300L, handoffMs = 1_300L))
    }

    @Test
    fun aConnectionRequestAloneDoesNotCountAsAServerReply() {
        val log = "Battle.net logon requested"
        val request = readLoginState(log)
        assertEquals(R.string.mobile_diagnostics_connecting, request.phase)
        assertTrue(browserConnectionStalled(request, 45_000L, frameMs = 4_300L, handoffMs = 1_300L))

        val reply = readLoginState("$log\nBattle.net front connected\nBattle.net logon queue update received")
        assertFalse(browserConnectionStalled(reply, 45_000L, frameMs = 4_300L, handoffMs = 1_300L))
    }

    @Test
    fun reportsARecognizedDisconnectWithoutRawLogData() {
        val log = """
            Battle.net front connected
            Battle.net logon form submission response authenticatorRequired="false" email="player@example.com"
            Fatal login error received result="Status has no name. (14400)"
        """.trimIndent()

        assertEquals(
            LoginState(
                R.string.mobile_diagnostics_error, "BLZ51914400", R.string.mobile_diagnostics_form_response,
                authenticatorRequired = false,
            ),
            readLoginState(log),
        )
    }

    @Test
    fun startsFreshAtTheNextSessionHeader() {
        val log = """
            Fatal login error received BLZ51914400
            Opened for Append
            Battle.net authentication server connected
            Battle.net logon form submission response authenticatorRequired="true"
        """.trimIndent()

        assertEquals(LoginState(R.string.mobile_diagnostics_authenticator, authenticatorRequired = true), readLoginState(log))
    }

    @Test
    fun reportsAuthenticatorFlagFromFatalResponseAfterSrp() {
        val log = """
            Battle.net front connected
            Battle.net external challenge received
            Battle.net SRP endpoint response received result="ERROR_OK (0)"
            Fatal login error received result="Status has no name. (14400)" authenticatorRequired="false"
        """.trimIndent()
        assertEquals(
            LoginState(
                R.string.mobile_diagnostics_error, "BLZ51914400", R.string.mobile_diagnostics_srp,
                authenticatorRequired = false,
            ),
            readLoginState(log),
        )
    }

    @Test
    fun newFailureIsDetectedAgainAndPreservesTheLastLoginPhase() {
        val auth = "Battle.net logon form submission response authenticatorRequired=\"true\""
        val first = readLoginState("$auth\n11/17 20:00:00.000 Fatal login error received (14400)")
        val second = readLoginState("$auth\n11/17 20:01:00.000 Fatal login error received (14400)")
        assertNotEquals(first, second)
        assertEquals(R.string.mobile_diagnostics_authenticator, second.failedAfter)
        assertTrue(second.showsLoginControls)
        assertFalse(readLoginState("Battle.net front connected").showsLoginControls)
    }
}
