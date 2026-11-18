package app.gamenative.ui.screen.xserver

import android.app.Application
import android.content.Context
import android.view.InputDevice
import android.view.MotionEvent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import app.gamenative.externaldisplay.normalizeMobileChat
import com.winlator.widget.TouchpadView
import com.winlator.xserver.Pointer
import com.winlator.xserver.XKeycode
import com.winlator.xserver.XServer
import io.mockk.every
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
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [34])
class MobileTouchControlsTest {
    @Test
    fun tapIsStillASingleFingerWhileTheStickAndCameraAreHeld() {
        checkSinglePointer(MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_DOWN)
        checkSinglePointer(MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP)
    }

    @Test
    fun liftingTheStickDoesNotEndAGameTouch() {
        val original = event(MotionEvent.ACTION_POINTER_UP, 0)
        try {
            assertNull(gameMotionEvent(original, setOf(19)))
        } finally {
            original.recycle()
        }
    }

    @Test
    fun gamePointerIndexIsRemappedWhenOtherFingersAreFiltered() {
        val original = event(MotionEvent.ACTION_POINTER_DOWN, 2)
        try {
            val filtered = gameMotionEvent(original, setOf(9, 19))
            assertNotNull(filtered)
            filtered!!
            assertEquals(MotionEvent.ACTION_POINTER_DOWN, filtered.actionMasked)
            assertEquals(1, filtered.actionIndex)
            assertEquals(19, filtered.getPointerId(1))
            filtered.recycle()
        } finally {
            original.recycle()
        }
    }

    @Test
    fun stickHasDeadZoneStraightMovementAndDiagonals() {
        assertEquals(emptySet<XKeycode>(), keysAt(.05f, -.08f))
        assertEquals(setOf(XKeycode.KEY_W), keysAt(.25f, -.85f))
        assertEquals(setOf(XKeycode.KEY_S, XKeycode.KEY_Q), keysAt(-.9f, .8f))
        assertEquals(setOf(XKeycode.KEY_E), keysAt(1f, -.1f))
    }

    @Test
    fun heldMovementSurvivesSmallThumbJitterAndStopsAtNeutral() {
        val diagonal = movementKeys(.68f, -.8f)
        assertEquals(diagonal, movementKeys(.41f, -.8f, diagonal))
        assertEquals(setOf(XKeycode.KEY_W), keysAt(.41f, -.8f))
        assertEquals(0, movementKeys(.04f, -.08f, diagonal))
    }

    @Test
    fun cameraAndShortcutsLeaveRoomForChatAndTheQuestColumn() {
        val layout = MobileLayout.fit(1536f, 709f, 32f, 0f, 0f)
        val questArea = Rect(1200f, 170f, 1536f, 300f)
        val chatArea = Rect(50f, 370f, 455f, 474f)
        assertFalse(layout.camera.overlaps(questArea))
        assertFalse(layout.stick.overlaps(chatArea))
        for ((shortcut, bounds) in layout.shortcuts) {
            assertEquals(shortcut, layout.shortcutAt(bounds.center))
            assertFalse(layout.camera.overlaps(bounds))
        }
    }

    @Test
    fun compactControlsFitTheBottomCornersWithinSafeInsets() {
        val width = 1300f
        val height = 720f
        val leftInset = 64f
        val rightInset = 32f
        val bottomInset = 26f
        val layout = MobileLayout.fit(width, height, leftInset, rightInset, bottomInset)
        assertTrue(layout.camera.width > layout.stick.width * 2f)
        assertEquals(layout.stick.bottom, layout.camera.bottom, .001f)
        assertTrue(layout.stick.left >= leftInset)
        assertTrue(layout.camera.right <= width - rightInset)
        assertTrue(layout.stick.width < height * .2f)
        assertTrue(layout.stick.top > height * .74f)
        assertTrue(layout.stick.bottom <= height - bottomInset)
        val jump = layout.shortcuts.getValue(MobileShortcut.Jump)
        assertTrue(jump.center.x > width * .66f)
        assertTrue(jump.right < layout.camera.left)

        val bounds = listOf(layout.stick, layout.camera) + layout.shortcuts.values
        bounds.forEachIndexed { index, control ->
            assertTrue(bounds.drop(index + 1).none(control::overlaps))
        }
    }

    @Test
    fun shortCameraSwipesUseAllTravelAndDoNotBecomeTaps() {
        val game = mockk<XServer>(relaxed = true)
        val pad = mockk<TouchpadView>(relaxed = true)
        val controls = MobileTouchControls(8f)
        controls.attach(game, pad)
        val layout = MobileLayout.fit(1536f, 709f, 32f, 0f, 0f)
        controls.updateLayout(layout)
        controls.togglePlaying()
        val origin = layout.camera.center

        fun send(action: Int, xOffset: Float) {
            val event = MotionEvent.obtain(
                100L, 140L, action, 1,
                arrayOf(MotionEvent.PointerProperties().apply { id = 9; toolType = MotionEvent.TOOL_TYPE_FINGER }),
                arrayOf(MotionEvent.PointerCoords().apply { x = origin.x + xOffset; y = origin.y }),
                0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0,
            )
            try {
                assertTrue(controls.route(event))
            } finally {
                event.recycle()
            }
        }

        send(MotionEvent.ACTION_DOWN, 0f)
        send(MotionEvent.ACTION_MOVE, 1f)
        assertFalse(controls.cameraHeld)
        send(MotionEvent.ACTION_MOVE, 4f)
        assertTrue(controls.cameraHeld)
        send(MotionEvent.ACTION_UP, 6f)
        verifyOrder {
            game.injectPointerButtonPress(Pointer.Button.BUTTON_RIGHT)
            pad.movePointerFromMobileLook(4f, 0f, 1f)
            pad.movePointerFromMobileLook(2f, 0f, 1f)
            game.injectPointerButtonRelease(Pointer.Button.BUTTON_RIGHT)
        }
        verify(exactly = 0) { pad.tapFromMobileLook(any(), any()) }
        assertFalse(controls.cameraHeld)
    }

    @Test
    fun draggedControlsKeepTheirRelativePositionAfterAResize() {
        val safeArea = Rect(64f, 20f, 1268f, 694f)
        val original = MobileLayout.fit(1300f, 720f, 64f, 32f, 26f)
        val position = safeArea.mobileHudPosition(original.camera, Offset(-10f, 2000f))

        val moved = MobileLayout.fit(
            970f,
            540f,
            35f,
            25f,
            15f,
            topInset = 15f,
            positions = mapOf(MobileHudElement.Camera to position),
        )
        assertEquals(0f, position.x, .001f)
        assertEquals(1f, position.y, .001f)
        assertEquals(35f, moved.camera.left, .001f)
        assertEquals(525f, moved.camera.bottom, .001f)
    }

    @Test
    fun hudPositionsCanBeSavedAndResetIndependentlyOfOtherSettings() {
        val preferences = RuntimeEnvironment.getApplication()
            .getSharedPreferences("hud-layout-test", Context.MODE_PRIVATE)
        preferences.edit().putFloat("camera_sensitivity", 1.25f).apply()
        val custom = mapOf(MobileHudElement.Camera to Offset(.73f, .56f), MobileHudElement.Toolbar to Offset(.2f, 0f))

        writeMobileHudPositions(preferences, custom)
        assertEquals(custom, readMobileHudPositions(preferences))

        writeMobileHudPositions(preferences, emptyMap())
        assertEquals(emptyMap<MobileHudElement, Offset>(), readMobileHudPositions(preferences))
        assertEquals(1.25f, preferences.getFloat("camera_sensitivity", 0f), .001f)
    }

    @Test
    fun editorsBlockPlayGesturesAndReleaseTheEditDragBeforeSaving() {
        val game = mockk<XServer>(relaxed = true)
        val pad = mockk<TouchpadView>(relaxed = true)
        every { pad.beginMobileEditorTouch(any(), any()) } returns true
        val controls = MobileTouchControls(8f)
        controls.attach(game, pad)
        controls.togglePlaying()
        controls.openHudEditor(MobileHudEditor.Controls)
        val touch = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 25f, 75f, 0)
        try {
            assertTrue(controls.route(touch))
            verify(exactly = 0) { pad.beginMobileEditorTouch(any(), any()) }
            controls.closeHudEditor()

            controls.openHudEditor(MobileHudEditor.Skills)
            assertTrue(controls.route(touch))
            controls.closeHudEditor(save = true)
            verifyOrder {
                game.injectKeyPress(XKeycode.KEY_F7, 0, false)
                pad.beginMobileEditorTouch(25f, 75f)
                pad.endMobileEditorTouch()
                game.injectKeyPress(XKeycode.KEY_F1, 0, false)
            }
            verify(exactly = 0) { pad.onTouchEvent(any()) }
            assertNull(controls.hudEditor)
        } finally {
            touch.recycle()
        }
    }

    @Test
    fun pastedGermanChatStaysOnOneLineAndKeepsSlashCommands() {
        assertEquals("/g Gruesse - fuer alle", normalizeMobileChat("/g Grüße —\nfür alle"))
    }

    @Test
    fun returningToLoginClearsPlayAndChatModes() {
        val controls = MobileTouchControls(8f)
        controls.togglePlaying()
        controls.setChatActive(true)
        controls.useLoginControls()
        assertFalse(controls.playing)
        assertFalse(controls.chatting)
    }

    private fun keysAt(x: Float, y: Float): Set<XKeycode> {
        val mask = movementKeys(x, y)
        return MOVEMENT_KEYS.filterIndexed { index, _ -> mask and (1 shl index) != 0 }.toSet()
    }

    private fun checkSinglePointer(rawAction: Int, expectedAction: Int) {
        val original = event(rawAction, 2)
        try {
            val filtered = gameMotionEvent(original, setOf(19))
            assertNotNull(filtered)
            filtered!!
            assertEquals(expectedAction, filtered.actionMasked)
            assertEquals(1, filtered.pointerCount)
            assertEquals(19, filtered.getPointerId(0))
            assertEquals(640f, filtered.x, 0f)
            assertEquals(217f, filtered.y, 0f)
            filtered.recycle()
        } finally {
            original.recycle()
        }
    }

    private fun event(action: Int, index: Int): MotionEvent = MotionEvent.obtain(
        100L, 140L, action or (index shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), 3,
        arrayOf(4, 9, 19).map { id ->
            MotionEvent.PointerProperties().apply { this.id = id; toolType = MotionEvent.TOOL_TYPE_FINGER }
        }.toTypedArray(),
        arrayOf(100f, 785f, 640f).map { x ->
            MotionEvent.PointerCoords().apply { this.x = x; y = 217f }
        }.toTypedArray(),
        0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0,
    )
}
