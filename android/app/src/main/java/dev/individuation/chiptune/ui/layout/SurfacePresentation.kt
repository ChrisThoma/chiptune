package dev.individuation.chiptune.ui.layout

/*
 * Which container each editor screen opens in, and where an anchored popover
 * lands. iOS gets both from `.popover` (which adapts back to a sheet when
 * compact) and `.sheet`; Compose has neither, so the rules are written out.
 */

/** The screens that change container with the window. */
enum class SurfaceKind { SONGS, ARRANGEMENT, EXPORT, INSTRUMENT_EDITOR, KEYBOARD_HELP }

enum class SurfaceContainer {
    /** A bottom sheet: every screen on a phone. */
    SHEET,

    /** Anchored to the control that opened it, the grid visible around it. */
    POPOVER,

    /** A centred card (the library on a tablet, iOS's form sheet). */
    DIALOG,

    /** Always on screen in the side column; nothing to open. */
    DOCKED,
}

object SurfaceContainers {
    /** The library dialog's widest. */
    const val LIBRARY_DIALOG_MAX_WIDTH = 640.0

    /** The library dialog's tallest, and its share of the window below that. */
    const val LIBRARY_DIALOG_MAX_HEIGHT = 760.0
    const val LIBRARY_DIALOG_HEIGHT_FRACTION = 0.85

    fun container(kind: SurfaceKind, layout: ChipLayout): SurfaceContainer = when {
        !layout.isRegularWidth -> SurfaceContainer.SHEET
        kind == SurfaceKind.SONGS -> SurfaceContainer.DIALOG
        kind == SurfaceKind.INSTRUMENT_EDITOR && layout.docksInstrumentEditor -> SurfaceContainer.DOCKED
        else -> SurfaceContainer.POPOVER
    }

    /** A popover's frame at text [scale]; [wrapsHeight] sizes it to its
     * content, with the room available as the cap. */
    data class Popover(val frame: PopoverSizing.Frame, val wrapsHeight: Boolean)

    fun popover(kind: SurfaceKind, scale: Double): Popover {
        val d = PopoverSizing.DEFAULT
        return when (kind) {
            SurfaceKind.ARRANGEMENT -> Popover(PopoverSizing.frame(d.minWidth, d.idealWidth, d.minHeight, 560.0, scale), false)
            // iOS's KeyboardHelpView: idealWidth 320, as tall as its rows.
            SurfaceKind.KEYBOARD_HELP -> Popover(PopoverSizing.frame(280.0, 320.0, 0.0, 0.0, scale), true)
            else -> Popover(PopoverSizing.frame(d.minWidth, d.idealWidth, d.minHeight, d.idealHeight, scale), false)
        }
    }

    fun libraryDialogWidth(windowWidth: Double): Double =
        minOf(LIBRARY_DIALOG_MAX_WIDTH, windowWidth - 2 * PopoverPlacement.MARGIN)

    fun libraryDialogHeight(windowHeight: Double): Double =
        minOf(LIBRARY_DIALOG_MAX_HEIGHT, windowHeight * LIBRARY_DIALOG_HEIGHT_FRACTION)
}

/**
 * Where a popover goes: under its anchor (iOS's `arrowEdge: .top`), or over
 * it when there's more room there, centred on it and kept [MARGIN] inside
 * the window. All values are in one unit (dp in the tests, px on device).
 */
object PopoverPlacement {
    const val MARGIN = 12.0

    /** Between the anchor and the popover's edge. */
    const val GAP = 8.0

    data class Bounds(val left: Double, val top: Double, val right: Double, val bottom: Double) {
        val width: Double get() = right - left
        val height: Double get() = bottom - top
        val centerX: Double get() = (left + right) / 2
    }

    /** The popover's box; for a wrapping one [height] is the cap. */
    data class Placement(val x: Double, val y: Double, val width: Double, val height: Double, val below: Boolean)

    fun place(
        anchor: Bounds?,
        frame: PopoverSizing.Frame,
        wrapsHeight: Boolean,
        window: Bounds,
        margin: Double = MARGIN,
        gap: Double = GAP,
    ): Placement {
        val width = maxOf(0.0, minOf(frame.idealWidth, window.width - 2 * margin))
        val usable = maxOf(0.0, window.height - 2 * margin)
        if (anchor == null) {
            val height = if (wrapsHeight) usable else minOf(frame.idealHeight, usable)
            return Placement(window.left + (window.width - width) / 2, window.top + (window.height - height) / 2, width, height, true)
        }
        val below = belowSpace(anchor, window, margin, gap)
        val above = aboveSpace(anchor, window, margin, gap)
        val target = if (wrapsHeight) 0.0 else frame.idealHeight
        val goesBelow = below >= minOf(target, frame.minHeight) || below >= above
        val room = if (goesBelow) below else above
        // The floor holds even when the room doesn't; the box then slides
        // to stay inside the window, over the anchor if it must.
        val floor = minOf(frame.minHeight, usable)
        val cap = maxOf(room, floor)
        val height = if (wrapsHeight) cap else minOf(frame.idealHeight, cap)
        val (x, y) = origin(anchor, width, height, window, margin, gap, goesBelow)
        return Placement(x, y, width, height, goesBelow)
    }

    /** The top-left for a box of a measured size: below the anchor when it
     * fits there or fits better there than above. */
    fun origin(
        anchor: Bounds?,
        width: Double,
        height: Double,
        window: Bounds,
        margin: Double = MARGIN,
        gap: Double = GAP,
        below: Boolean? = null,
    ): Pair<Double, Double> {
        if (anchor == null) {
            return Pair(window.left + (window.width - width) / 2, window.top + (window.height - height) / 2)
        }
        val goesBelow = below ?: (belowSpace(anchor, window, margin, gap) >= height ||
            belowSpace(anchor, window, margin, gap) >= aboveSpace(anchor, window, margin, gap))
        val x = clamp(anchor.centerX - width / 2, window.left + margin, window.right - margin - width)
        val rawY = if (goesBelow) anchor.bottom + gap else anchor.top - gap - height
        val y = clamp(rawY, window.top + margin, window.bottom - margin - height)
        return Pair(x, y)
    }

    private fun belowSpace(anchor: Bounds, window: Bounds, margin: Double, gap: Double) =
        window.bottom - margin - (anchor.bottom + gap)

    private fun aboveSpace(anchor: Bounds, window: Bounds, margin: Double, gap: Double) =
        anchor.top - gap - (window.top + margin)

    /** Low wins when the range is empty (a box wider than the window). */
    private fun clamp(value: Double, low: Double, high: Double): Double = maxOf(low, minOf(value, high))
}
