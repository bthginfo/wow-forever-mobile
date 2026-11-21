package app.gamenative.ui.screen.wow

import android.content.Context
import android.os.Build
import app.gamenative.BuildConfig
import com.winlator.core.GPUInformation

internal enum class GpuProfile(
    val driver: String,
    val bundledDriver: String?,
    val tuDebug: String?,
    val screenSize: String,
    val edition: String,
    val graphicsWrapper: String = "Wrapper",
    val dxvkVersion: String = "2.4.1-wow-aarch64-test",
) {
    ADRENO_7XX(
        "Turnip-WoW-scheduler-test",
        "turnip-wow-scheduler-test.zip",
        "noconform",
        "1600x900",
        "Snapdragon 8 Series / Adreno 7xx",
    ),
    ADRENO_8XX(
        "Turnip-V32-RP6sched",
        "turnip-V32-RP6sched.zip",
        "noconform,sysmem",
        "1280x720",
        "Snapdragon 8 Elite / Adreno 8xx",
    ),
    PIXEL_MALI(
        "System",
        null,
        null,
        "1280x720",
        "Pixel / Mali Vulkan",
        graphicsWrapper = "Wrapper-GameNative",
        dxvkVersion = "2.4.1-wow-powervr",
    ),
    PIXEL_10(
        "System",
        null,
        null,
        "1280x720",
        "Pixel 10 / PowerVR Vulkan",
        graphicsWrapper = "Wrapper-GameNative",
        dxvkVersion = "2.4.1-wow-powervr",
    );

    val graphicsDriverConfig: String
        get() = if (driver == "System") {
            "version=$driver,adrenotoolsTurnip=0,vulkanVersion=1.3,gpuName=Device,presentMode=fifo," +
                "resourceType=auto,bcnEmulation=auto,bcnEmulationCache=1,quality=high"
        } else {
            "version=$driver,adrenotoolsTurnip=1,resourceType=buffer,bcnEmulation=auto,quality=high"
        }

    companion object {
        private val maliPixelModels = setOf("Pixel Fold", "Pixel 9", "Pixel 9 Pro", "Pixel 9 Pro XL", "Pixel 9 Pro Fold")
        private val pixel10Models = setOf("Pixel 10", "Pixel 10 Pro", "Pixel 10 Pro XL", "Pixel 10 Pro Fold")

        fun detect(context: Context): GpuProfile =
            select(BuildConfig.PIXEL_VULKAN_TEST, Build.MANUFACTURER, Build.MODEL, Build.DEVICE) {
                isAdreno8xxDevice(context)
            }

        fun select(
            pixelVulkanTestEnabled: Boolean,
            manufacturer: String,
            model: String,
            device: String = "",
            isAdreno8xx: () -> Boolean,
        ): GpuProfile {
            if (pixelVulkanTestEnabled && manufacturer.equals("Google", ignoreCase = true)) {
                if (model in maliPixelModels || device.equals("felix", ignoreCase = true)) return PIXEL_MALI
                if (model in pixel10Models) return PIXEL_10
            }
            return if (isAdreno8xx()) ADRENO_8XX else ADRENO_7XX
        }

        private fun isAdreno8xxDevice(context: Context): Boolean {
            if (GPUInformation.isAdreno8Elite(context)) return true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val soc = Build.SOC_MODEL
                if (listOf("SM8735", "SM8750", "SM8845", "SM8850").any { soc.contains(it, ignoreCase = true) }) return true
            }
            return Build.HARDWARE.contains("sun", ignoreCase = true)
        }
    }
}
