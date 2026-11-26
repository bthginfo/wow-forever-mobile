package app.gamenative.ui.screen.xserver

import android.app.Application
import android.view.InputDevice
import android.view.MotionEvent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import com.winlator.widget.TouchpadView
import com.winlator.xserver.XKeycode
import com.winlator.xserver.XServer
import io.mockk.mockk
import io.mockk.verify
import io.mockk.verifyOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [34])
class MobileTouchFeelTest {
    private val game = mockk<XServer>(relaxed = true)
    private val pad = mockk<TouchpadView>(relaxed = true)
    private val layout = MobileLayout.fit(1536f, 709f, 32f, 0f, 0f)
    private val controls = MobileTouchControls(8f).apply {
        attach(game, pad)
        updateLayout(layout)
        togglePlaying()
    }

    @Test
    fun theStickZoneReachesTheEdgesWithoutCoveringOtherControlsOrTheSkillArc() {
        val zone = layout.stickZone
        assertTrue(zone.contains(layout.stick.topLeft))
        assertTrue(zone.contains(layout.stick.bottomRight - Offset(1f, 1f)))
        assertEquals(32f, zone.left, .001f)
        assertEquals(709f, zone.bottom, .001f)
        assertTrue(zone.right > layout.stick.right + layout.stick.width * .4f)
        // The left skill arc starts 23 % above the bottom edge.
        assertTrue(zone.top > 709f * (1f - .23f))
        assertFalse(zone.overlaps(layout.camera))
        for (bounds in layout.shortcuts.values) assertFalse(zone.overlaps(bounds))
    }

    @Test
    fun aMovedStickTakesItsZoneWithItAndStaysInsideTheSafeArea() {
        val moved = MobileLayout.fit(
            1536f, 709f, 32f, 0f, 0f, 12f,
            positions = mapOf(MobileHudElement.Movement to Offset(0f, 0f)),
        )
        val safeArea = Rect(32f, 12f, 1536f, 709f)
        assertTrue(moved.stickZone.contains(moved.stick.center))
        assertEquals(safeArea.left, moved.stickZone.left, .001f)
        assertEquals(safeArea.top, moved.stickZone.top, .001f)
    }

    @Test
    fun aTouchBesideTheStickMovesTheCharacterInsteadOfClickingTheWorld() {
        val beside = Offset(layout.stick.right + layout.stick.width * .3f, layout.stick.center.y)
        assertFalse(layout.stick.contains(beside))
        assertTrue(layout.stickZone.contains(beside))

        send(MotionEvent.ACTION_DOWN, 3, beside)
        assertNotNull(controls.stickAnchor)
        send(MotionEvent.ACTION_MOVE, 3, beside - Offset(0f, layout.stick.width))
        send(MotionEvent.ACTION_UP, 3, beside - Offset(0f, layout.stick.width))

        verifyOrder {
            game.injectKeyPress(XKeycode.KEY_W, 0, false)
            game.injectKeyRelease(XKeycode.KEY_W)
        }
        verify(exactly = 0) { pad.onTouchEvent(any()) }
        assertNull(controls.stickAnchor)
    }

    @Test
    fun touchesOutsideTheStickZoneStillReachTheGame() {
        val world = Offset(768f, 300f)
        assertFalse(layout.stickZone.contains(world))
        send(MotionEvent.ACTION_DOWN, 3, world)
        assertNull(controls.stickAnchor)
        verify { pad.onTouchEvent(any()) }
    }

    @Test
    fun jumpIsHeldForAsLongAsTheThumbStaysOnIt() {
        val jump = layout.shortcuts.getValue(MobileShortcut.Jump).center
        send(MotionEvent.ACTION_DOWN, 5, jump)
        verify { game.injectKeyPress(XKeycode.KEY_SPACE, 0, false) }
        verify(exactly = 0) { game.injectKeyRelease(XKeycode.KEY_SPACE) }
        assertEquals(setOf(MobileShortcut.Jump), controls.pressedShortcuts)

        send(MotionEvent.ACTION_UP, 5, jump)
        verify(exactly = 1) { game.injectKeyRelease(XKeycode.KEY_SPACE) }
        assertEquals(emptySet<MobileShortcut>(), controls.pressedShortcuts)
    }

    @Test
    fun targetAndInteractFireOnTouchDown() {
        val target = layout.shortcuts.getValue(MobileShortcut.Target).center
        send(MotionEvent.ACTION_DOWN, 6, target)
        verifyOrder {
            game.injectKeyPress(XKeycode.KEY_CTRL_L, 0, false)
            game.injectKeyPress(XKeycode.KEY_SHIFT_L, 0, false)
            game.injectKeyPress(XKeycode.KEY_F12, 0, false)
            game.injectKeyRelease(XKeycode.KEY_F12)
        }
        // Lifting the finger elsewhere neither repeats nor cancels the press.
        send(MotionEvent.ACTION_UP, 6, Offset(768f, 300f))
        verify(exactly = 1) { game.injectKeyPress(XKeycode.KEY_F12, 0, false) }
        verify(exactly = 0) { pad.onTouchEvent(any()) }
    }

    @Test
    fun aCancelledGestureReleasesAHeldJump() {
        val jump = layout.shortcuts.getValue(MobileShortcut.Jump).center
        send(MotionEvent.ACTION_DOWN, 5, jump)
        send(MotionEvent.ACTION_CANCEL, 5, jump)
        verify(exactly = 1) { game.injectKeyRelease(XKeycode.KEY_SPACE) }
        assertEquals(emptySet<MobileShortcut>(), controls.pressedShortcuts)

        send(MotionEvent.ACTION_DOWN, 5, jump)
        controls.useLoginControls()
        verify(exactly = 2) { game.injectKeyRelease(XKeycode.KEY_SPACE) }
    }

    private fun send(action: Int, id: Int, position: Offset) {
        val event = MotionEvent.obtain(
            100L, 140L, action, 1,
            arrayOf(
                MotionEvent.PointerProperties().apply {
                    this.id = id
                    toolType = MotionEvent.TOOL_TYPE_FINGER
                },
            ),
            arrayOf(
                MotionEvent.PointerCoords().apply {
                    x = position.x
                    y = position.y
                },
            ),
            0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0,
        )
        try {
            assertTrue(controls.route(event))
        } finally {
            event.recycle()
        }
    }
}
