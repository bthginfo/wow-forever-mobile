package app.gamenative.ui.screen.xserver

import android.os.Build
import android.view.Display
import android.view.Window
import kotlin.math.abs
import kotlin.math.roundToInt

/** Frames per second while the game runs hidden. It keeps the Battle.net session alive at a fraction of the work. */
internal const val BACKGROUND_FRAME_LIMIT = 10

/** The frame cap to use while the app is not visible. A lower cap the player chose stays in effect. */
internal fun backgroundFrameLimit(foregroundLimit: Int): Int =
    if (foregroundLimit in 1..BACKGROUND_FRAME_LIMIT) foregroundLimit else BACKGROUND_FRAME_LIMIT

/**
 * The lowest display refresh rate that shows each of [fps] frames for the same number of refreshes.
 *
 * A capped game gains nothing from a faster panel, and a 120 Hz panel draws twice as often as a 60 FPS game needs.
 * Returns null when there is no cap, so the system keeps choosing.
 */
internal fun preferredRefreshRate(fps: Int, supported: Collection<Float>, floor: Float = MIN_PREFERRED_REFRESH_HZ): Float? {
    if (fps <= 0) return null
    val minimum = maxOf(fps.toFloat(), floor) - .5f
    val candidates = supported.filter { it.isFinite() && it >= minimum }.sorted()
    if (candidates.isEmpty()) return null
    return candidates.firstOrNull { rate ->
        val ratio = rate / fps
        abs(ratio - ratio.roundToInt()) < .02f
    } ?: candidates.first()
}

/** Refresh rates of the display modes that keep the current resolution. */
internal fun Display.refreshRatesAtCurrentResolution(): List<Float> {
    val current = mode
    return supportedModes
        .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
        .map { it.refreshRate }
}

/**
 * Asks for a panel refresh rate that matches the game's frame cap and turns off the touch boost to the panel's
 * maximum rate, which a thumb resting on the stick would otherwise trigger for the whole session.
 * Returns a function that restores the window's previous settings.
 */
internal fun Window.preferGameFrameRate(frameLimit: Int): () -> Unit {
    val previousRate = attributes.preferredRefreshRate
    val display = decorView.display
    val target = display?.let { preferredRefreshRate(frameLimit, it.refreshRatesAtCurrentResolution()) }
    if (target != null && target != previousRate) {
        attributes = attributes.apply { preferredRefreshRate = target }
    }
    val previousBoost = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
        frameRateBoostOnTouchEnabled.also { if (frameLimit > 0) frameRateBoostOnTouchEnabled = false }
    } else {
        null
    }
    return {
        if (attributes.preferredRefreshRate != previousRate) {
            attributes = attributes.apply { preferredRefreshRate = previousRate }
        }
        if (previousBoost != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            frameRateBoostOnTouchEnabled = previousBoost
        }
    }
}

// Keeps the touch overlay responsive when a player caps the game below 60 FPS.
private const val MIN_PREFERRED_REFRESH_HZ = 60f
