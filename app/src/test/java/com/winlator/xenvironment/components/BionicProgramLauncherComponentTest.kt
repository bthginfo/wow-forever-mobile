package com.winlator.xenvironment.components

import android.app.Application
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import app.gamenative.PluviaApp
import com.winlator.core.Callback
import com.winlator.core.ProcessHelper
import com.winlator.xenvironment.ImageFs
import com.winlator.xenvironment.XEnvironment
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class BionicProgramLauncherComponentTest {
    @Test
    fun ignoresLateExitFromAnIntentionalStopAndReportsAnUnexpectedExitFromTheNewGame() {
        val callbacks = mutableListOf<Callback<Int>>()
        val statuses = mutableListOf<Int>()
        val app = ApplicationProvider.getApplicationContext<Application>()
        mockkStatic(ProcessHelper::class)
        try {
            every { ProcessHelper.exec(any(), any<Array<String>>(), any<File>(), capture(callbacks)) } returns
                Int.MAX_VALUE
            every { ProcessHelper.listSubProcesses() } returns emptyList()

            fun launcher() = object : BionicProgramLauncherComponent(mockk(), null) {
                override fun execShellCommand(command: String) = ""
            }.also { component ->
                XEnvironment(app, ImageFs.find(app)).addComponent(component)
                component.setTerminationCallback { statuses.add(it) }
            }

            val original = launcher()
            original.launchGuestProcess("wine", emptyArray(), app.filesDir)
            original.stop()
            launcher().launchGuestProcess("wine", emptyArray(), app.filesDir)

            callbacks[0].call(137)
            shadowOf(Looper.getMainLooper()).idle()
            assertTrue(statuses.isEmpty())
            assertTrue(PluviaApp.keepAlive)

            callbacks[1].call(137)
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(listOf(137), statuses)
            assertFalse(PluviaApp.keepAlive)
        } finally {
            PluviaApp.keepAlive = false
            unmockkStatic(ProcessHelper::class)
        }
    }
}
