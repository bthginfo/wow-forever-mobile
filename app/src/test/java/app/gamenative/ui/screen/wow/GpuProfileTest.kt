package app.gamenative.ui.screen.wow

import com.winlator.core.KeyValueSet
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GpuProfileTest {
    @Test
    fun pixel10ModelsUseSystemVulkanInTheTestBuild() {
        for (model in listOf("Pixel 10", "Pixel 10 Pro", "Pixel 10 Pro XL", "Pixel 10 Pro Fold")) {
            val profile = GpuProfile.select(true, "Google", model) { error("Pixel should skip Adreno detection") }
            val config = KeyValueSet(profile.graphicsDriverConfig)

            assertEquals(GpuProfile.PIXEL_10, profile)
            assertEquals("System", config.get("version"))
            assertEquals("0", config.get("adrenotoolsTurnip"))
            assertEquals("1.3", config.get("vulkanVersion"))
            assertNull(profile.bundledDriver)
            assertNull(profile.tuDebug)
        }
    }

    @Test
    fun pixelBaseBuildAndOtherGoogleModelsKeepTheExistingSelection() {
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(false, "Google", "Pixel 10") { false })
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(true, "Google", "Pixel 10a") { false })
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(true, "Google", "Pixel 9") { false })
    }

    @Test
    fun snapdragonDevicesKeepTheirTurnipDriversInTheTestBuild() {
        val older = GpuProfile.select(true, "Samsung", "SM-S928B") { false }
        val newer = GpuProfile.select(true, "Samsung", "SM-S938B") { true }

        assertEquals("turnip-wow-scheduler-test.zip", older.bundledDriver)
        assertEquals("turnip-V32-RP6sched.zip", newer.bundledDriver)
        assertEquals("1", KeyValueSet(older.graphicsDriverConfig).get("adrenotoolsTurnip"))
        assertEquals("1", KeyValueSet(newer.graphicsDriverConfig).get("adrenotoolsTurnip"))
    }
}
