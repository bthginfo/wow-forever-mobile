package app.gamenative.ui.screen.wow

import com.winlator.core.KeyValueSet
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GpuProfileTest {
    @Test
    fun originalPixelFoldUsesTheMaliVulkanPath() {
        val fold = GpuProfile.select(true, "Google", "Pixel Fold") {
            error("The Tensor G2 Pixel Fold should skip Adreno detection")
        }
        val foldByDevice = GpuProfile.select(true, "Google", "AOSP Fold", "felix") {
            error("The felix device should skip Adreno detection")
        }
        val config = KeyValueSet(fold.graphicsDriverConfig)

        assertEquals(GpuProfile.PIXEL_MALI, fold)
        assertEquals(fold, foldByDevice)
        assertEquals("System", config.get("version"))
        assertEquals("0", config.get("adrenotoolsTurnip"))
        assertEquals("Wrapper-GameNative", fold.graphicsWrapper)
        assertEquals("2.4.1-wow-powervr", fold.dxvkVersion)
        assertEquals("1280x720", fold.screenSize)
        assertNull(fold.bundledDriver)
        assertNull(fold.tuDebug)
    }

    @Test
    fun pixel9ModelsUseSystemMaliVulkanInTheTestBuild() {
        for (model in listOf("Pixel 9", "Pixel 9 Pro", "Pixel 9 Pro XL", "Pixel 9 Pro Fold")) {
            val profile = GpuProfile.select(true, "Google", model) { error("Pixel should skip Adreno detection") }
            val config = KeyValueSet(profile.graphicsDriverConfig)

            assertEquals(GpuProfile.PIXEL_MALI, profile)
            assertEquals("Wrapper-GameNative", profile.graphicsWrapper)
            assertEquals("2.4.1-wow-powervr", profile.dxvkVersion)
            assertEquals("System", config.get("version"))
            assertEquals("0", config.get("adrenotoolsTurnip"))
            assertEquals("1.3", config.get("vulkanVersion"))
            assertEquals("auto", config.get("bcnEmulation"))
            assertEquals("1", config.get("bcnEmulationCache"))
            assertNull(profile.bundledDriver)
            assertNull(profile.tuDebug)
        }
    }

    @Test
    fun pixel10ModelsUseSystemVulkanInTheTestBuild() {
        for (model in listOf("Pixel 10", "Pixel 10 Pro", "Pixel 10 Pro XL", "Pixel 10 Pro Fold")) {
            val profile = GpuProfile.select(true, "Google", model) { error("Pixel should skip Adreno detection") }
            val config = KeyValueSet(profile.graphicsDriverConfig)

            assertEquals(GpuProfile.PIXEL_10, profile)
            assertEquals("Wrapper-GameNative", profile.graphicsWrapper)
            assertEquals("2.4.1-wow-powervr", profile.dxvkVersion)
            assertEquals("System", config.get("version"))
            assertEquals("0", config.get("adrenotoolsTurnip"))
            assertEquals("1.3", config.get("vulkanVersion"))
            assertEquals("1", config.get("bcnEmulationCache"))
            assertNull(profile.bundledDriver)
            assertNull(profile.tuDebug)
        }
    }

    @Test
    fun pixelBaseBuildAndOtherGoogleModelsKeepTheExistingSelection() {
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(false, "Google", "Pixel Fold", "felix") { false })
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(true, "Samsung", "Pixel Fold", "felix") { false })
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(false, "Google", "Pixel 9 Pro XL") { false })
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(false, "Google", "Pixel 10") { false })
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(true, "Google", "Pixel 10a") { false })
        assertEquals(GpuProfile.ADRENO_7XX, GpuProfile.select(true, "Google", "Pixel 9a") { false })
    }

    @Test
    fun snapdragonDevicesKeepTheirTurnipDriversInTheTestBuild() {
        val older = GpuProfile.select(true, "Samsung", "SM-S928B") { false }
        val newer = GpuProfile.select(true, "Samsung", "SM-S938B") { true }

        assertEquals("turnip-wow-scheduler-test.zip", older.bundledDriver)
        assertEquals("turnip-V32-RP6sched.zip", newer.bundledDriver)
        assertEquals("Wrapper", older.graphicsWrapper)
        assertEquals("Wrapper", newer.graphicsWrapper)
        assertEquals("2.4.1-wow-aarch64-test", older.dxvkVersion)
        assertEquals("2.4.1-wow-aarch64-test", newer.dxvkVersion)
        assertEquals("1", KeyValueSet(older.graphicsDriverConfig).get("adrenotoolsTurnip"))
        assertEquals("1", KeyValueSet(newer.graphicsDriverConfig).get("adrenotoolsTurnip"))
    }
}
