package app.gamenative.ui.screen.wow

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import com.winlator.renderer.VulkanRenderer
import com.winlator.widget.XServerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import kotlin.coroutines.resume
import kotlin.math.roundToInt

internal class MobileArcSaver(private val gameRoot: File, private val session: String) {
    private var previousSerial: Int? = null

    suspend fun save(view: XServerView, request: () -> Unit): Boolean {
        val renderer = view.renderer as? VulkanRenderer ?: return false
        val transfer = MobileArcTransfer(session, previousSerial)
        val pixels = Bitmap.createBitmap(ARC_COLUMNS * 3, ARC_ROWS * 3, Bitmap.Config.ARGB_8888)
        val handler = Handler(Looper.getMainLooper())
        request()
        val snapshot = withTimeoutOrNull(3400) {
            var decoded: MobileArcSnapshot? = null
            while (decoded == null) {
                val bounds = renderer.gameSurfaceBounds
                val crop = Rect(
                    (bounds.left + bounds.width() / 4).roundToInt(),
                    (bounds.top + bounds.height() / 3).roundToInt(),
                    (bounds.right - bounds.width() / 4).roundToInt(),
                    (bounds.bottom - bounds.height() / 3).roundToInt(),
                )
                if (crop.width() >= ARC_COLUMNS && crop.height() >= ARC_ROWS &&
                    view.holder.surfaceFrame.contains(crop) && view.holder.surface.isValid &&
                    copyFrame(view, crop, pixels, handler)
                ) {
                    decoded = withContext(Dispatchers.Default) {
                        transfer.readFrame { index -> pixels.getPixel(index % ARC_COLUMNS * 3 + 1, index / ARC_COLUMNS * 3 + 1) }
                    }
                }
                if (decoded == null) delay(24)
            }
            decoded
        } ?: return false
        previousSerial = snapshot.serial
        withContext(Dispatchers.IO) { saveMobileArcProfile(gameRoot, snapshot.data) }
        return true
    }

    private suspend fun copyFrame(view: XServerView, rect: Rect, pixels: Bitmap, handler: Handler): Boolean =
        suspendCancellableCoroutine { result ->
            try {
                PixelCopy.request(view.holder.surface, rect, pixels, { status ->
                    result.resume(status == PixelCopy.SUCCESS)
                }, handler)
            } catch (_: IllegalArgumentException) {
                result.resume(false)
            }
        }
}
