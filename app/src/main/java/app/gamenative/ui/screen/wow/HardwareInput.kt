package app.gamenative.ui.screen.wow

import android.os.Build
import android.view.InputDevice
import com.winlator.xserver.Keyboard

internal data class HardwareInput(val keyboard: Boolean, val mouse: Boolean) {
    val desktop: Boolean get() = keyboard && mouse

    companion object {
        fun connected(): HardwareInput {
            val devices = InputDevice.getDeviceIds().mapNotNull(InputDevice::getDevice)
                .filter { !it.isVirtual && it.isEnabled && (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || it.isExternal) }
            return HardwareInput(devices.any(Keyboard::isKeyboardDevice), devices.any(::isMouse))
        }

        fun isMouse(device: InputDevice): Boolean = device.supportsSource(InputDevice.SOURCE_MOUSE) ||
            device.supportsSource(InputDevice.SOURCE_MOUSE_RELATIVE) ||
            device.supportsSource(InputDevice.SOURCE_TOUCHPAD)
    }
}
