package app.gamenative.ui.screen.wow

import android.content.res.Configuration

internal val Configuration.usesTabletLayout: Boolean
    get() = minOf(screenWidthDp, screenHeightDp) >= 600
