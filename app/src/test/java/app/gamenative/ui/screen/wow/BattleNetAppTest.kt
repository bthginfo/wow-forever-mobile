package app.gamenative.ui.screen.wow

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class BattleNetAppTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()

    @Test
    fun opensTheInstalledBattleNetAppWithoutPassingGameData() {
        val battleNetPackage = "com.blizzard.messenger"
        val entry = "$battleNetPackage.Main"
        val launchIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(battleNetPackage)
        val resolution = ResolveInfo().apply {
            activityInfo = ActivityInfo().apply {
                packageName = battleNetPackage
                name = entry
                applicationInfo = ApplicationInfo().apply { packageName = battleNetPackage }
            }
        }
        shadowOf(app.packageManager).addResolveInfoForIntent(launchIntent, resolution)

        assertTrue(openBattleNetApp(app))
        val started = shadowOf(app).nextStartedActivity
        assertEquals(ComponentName(battleNetPackage, entry), started.component)
        assertTrue(started.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertNull(started.data)
        assertNull(started.extras)
    }

    @Test
    fun leavesTheUserInWowWhenTheCompanionIsUnavailable() {
        assertFalse(openBattleNetApp(app))
        assertNull(shadowOf(app).nextStartedActivity)
    }
}
