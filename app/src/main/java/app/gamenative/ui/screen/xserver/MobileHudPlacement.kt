package app.gamenative.ui.screen.xserver

import android.content.SharedPreferences
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect

internal enum class MobileHudElement {
    Movement, Camera, Jump, Target, Interact, Toolbar,
}

internal enum class MobileHudEditor {
    Controls, Skills,
}

internal fun readMobileHudPositions(preferences: SharedPreferences): Map<MobileHudElement, Offset> =
    MobileHudElement.entries.mapNotNull { element ->
        val x = preferences.getFloat(element.positionKey("x"), Float.NaN)
        val y = preferences.getFloat(element.positionKey("y"), Float.NaN)
        if (x in 0f..1f && y in 0f..1f) element to Offset(x, y) else null
    }.toMap()

internal fun writeMobileHudPositions(preferences: SharedPreferences, positions: Map<MobileHudElement, Offset>) {
    val edit = preferences.edit()
    for (element in MobileHudElement.entries) {
        val position = positions[element]
        if (position != null) {
            edit.putFloat(element.positionKey("x"), position.x)
            edit.putFloat(element.positionKey("y"), position.y)
        } else {
            edit.remove(element.positionKey("x"))
            edit.remove(element.positionKey("y"))
        }
    }
    edit.apply()
}

// Store a point within the distance this element can travel on each axis.
// Using its own travel range keeps the entire control within the safe area after a resize.
internal fun Rect.mobileHudPosition(bounds: Rect, center: Offset): Offset {
    val travelX = width - bounds.width
    val travelY = height - bounds.height
    return Offset(
        if (travelX > 0f) ((center.x - left - bounds.width / 2f) / travelX).coerceIn(0f, 1f) else .5f,
        if (travelY > 0f) ((center.y - top - bounds.height / 2f) / travelY).coerceIn(0f, 1f) else .5f,
    )
}

internal fun Rect.placeMobileHudElement(bounds: Rect, position: Offset?): Rect {
    if (position == null || isEmpty) return bounds
    val x = left + ((width - bounds.width).coerceAtLeast(0f) * position.x)
    val y = top + ((height - bounds.height).coerceAtLeast(0f) * position.y)
    return bounds.translate(x - bounds.left, y - bounds.top)
}

private fun MobileHudElement.positionKey(axis: String) = "hud_position_${name}_$axis"
