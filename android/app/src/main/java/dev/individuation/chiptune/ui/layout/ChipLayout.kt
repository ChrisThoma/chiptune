package dev.individuation.chiptune.ui.layout

/*
 * Port of `Sources/Views/Layout.swift`. Pure: no Compose, so the rules run in
 * JVM tests. All sizes are dp, the iOS points one for one.
 */

/** iOS's horizontal size class, read from the window width. */
enum class SizeClass {
    COMPACT, REGULAR;

    companion object {
        /** Window width (not `smallestScreenWidthDp`) at which the pad metrics apply. */
        const val REGULAR_MIN_WIDTH_DP = 600.0

        fun forWindowWidth(widthDp: Double): SizeClass =
            if (widthDp >= REGULAR_MIN_WIDTH_DP) REGULAR else COMPACT
    }
}

/** The size [LayoutResolver.resolve] reads: the window less the status bar,
 * navigation bar and cutout, but never less the on-screen keyboard. */
data class WindowSize(val width: Double, val height: Double)

/** Which way the grid and the keys run. */
enum class EditorAxis { VERTICAL, HORIZONTAL }

/** The shapes the transport takes below accessibility text sizes. */
enum class TransportForm {
    /** Play, the mode tray and BPM on one row. */
    ROW,
    /** Play and the mode tray, then BPM full width under them. */
    TWO_ROWS,
    /** Play, the mode tray and BPM each on a row of their own. */
    STACKED,
}

/**
 * Sizes that differ between a phone window and a tablet one. The editor is
 * one screen, so adapting it is metrics plus one structural choice (keys
 * under the grid, or beside it).
 */
data class ChipLayout(
    /** Height of one step row in the grid. */
    val gridRowHeight: Double,
    /** Floor for a track column's width; past this the grid scrolls sideways. */
    val gridMinColumnWidth: Double,
    /** The step-number column down the left of the grid. */
    val gridGutterWidth: Double,
    /** Track header box, matched by the "+" column beside it. */
    val trackHeaderHeight: Double,
    /** The white keys, not counting the octave/note row above them. */
    val keyboardHeight: Double,
    /** Keys stop growing here and centre in the space left. */
    val keyboardMaxWidth: Double,
    /** Type size of the note names on the key caps. */
    val keyLabelSize: Double,
    /** Widest the transport and pattern rows get before they centre. */
    val chromeMaxWidth: Double,
    /** Height of the transport/pattern trays and their chips, before text scaling. */
    val trayHeight: Double,
    /** Width of a stepper's minus/plus ends, before text scaling. */
    val stepperEndWidth: Double,
    /** Width of the undo/redo buttons beside the song name. */
    val historyButtonWidth: Double,
    /** The tappable square around a title-bar icon (Songs, the menu). */
    val titleIconTargetSize: Double,
    /** Size of the glyph inside that square. */
    val titleIconGlyphSize: Double,
    /** Width of a PATT or SONG segment. */
    val patternSegmentWidth: Double,
    /** Width of the ARR button. */
    val arrButtonWidth: Double,
    /** Minimum width of a pattern chip. */
    val patternChipWidth: Double,
    /** Width of the "+" button that adds a pattern. */
    val patternAddWidth: Double,
    /** Tablet-shaped window rather than phone-shaped. */
    val isRegularWidth: Boolean,
    /** How wide the keyboard column is in the side arrangement. */
    val sideColumnWidth: Double,
    /** Octaves of piano the keyboard draws. */
    val keyboardOctaves: Int,
    /** Grid and keyboard side by side rather than stacked. */
    val usesSideKeyboard: Boolean,
    /** About what the title, transport and pattern rows stand together. */
    val chromeHeight: Double,
    /** The divider, gaps, octave row and keys under the grid when stacked. */
    val stackedKeysHeight: Double,
    /** Too short for the fixed editor: the whole editor scrolls instead. */
    val scrollsEditor: Boolean = false,
) {
    /** The selected track's sound controls live in the side column. */
    val docksInstrumentEditor: Boolean get() = usesSideKeyboard

    /** Only the container's axis changes between the two arrangements. */
    val editorAxis: EditorAxis get() = if (usesSideKeyboard) EditorAxis.HORIZONTAL else EditorAxis.VERTICAL

    /** Anchored to the track header rather than a sheet over the editor. */
    val presentsInstrumentAsPopover: Boolean get() = isRegularWidth && !usesSideKeyboard

    /** The scrolling (large text) editor always stacks, so nothing may think
     * the instrument editor is docked. */
    val withoutDockedInstrumentEditor: ChipLayout get() = copy(usesSideKeyboard = false)

    /** Everything in the fixed editor that isn't grid rows. */
    val editorFixedHeight: Double
        get() = chromeHeight + trackHeaderHeight + 7 + (if (usesSideKeyboard) 8.0 else stackedKeysHeight)

    /** The narrowest the one-row transport draws. [stepperEndScale] is the
     * text-size ratio the stepper ends grow by. */
    fun transportRowMinimumWidth(stepperEndScale: Double = 1.0): Double =
        CHROME_ROW_PADDING * 2 + PLAY_BUTTON_WIDTH + transportModeTrayWidth + TRANSPORT_TRAY_GAP +
            transportStepperWidth(stepperEndScale) + CHROME_ROW_SPACING * 3

    /** The narrowest the stacked transport draws. */
    fun transportStackMinimumWidth(stepperEndScale: Double = 1.0): Double =
        CHROME_ROW_PADDING * 2 + maxOf(
            PLAY_BUTTON_WIDTH + CHROME_ROW_SPACING,
            transportModeTrayWidth,
            transportStepperWidth(stepperEndScale),
        )

    fun transportRowFits(width: Double, stepperEndScale: Double = 1.0): Boolean =
        transportRowMinimumWidth(stepperEndScale) <= width

    /** The narrowest the two-row transport draws. */
    fun transportTwoRowMinimumWidth(stepperEndScale: Double = 1.0): Double =
        CHROME_ROW_PADDING * 2 + maxOf(
            PLAY_BUTTON_WIDTH + CHROME_ROW_SPACING + transportModeTrayWidth,
            transportStepperWidth(stepperEndScale),
        )

    /** The first form that fits a chrome [width] wide: row, two rows, stacked. */
    fun transportForm(width: Double, stepperEndScale: Double = 1.0): TransportForm = when {
        transportRowFits(width, stepperEndScale) -> TransportForm.ROW
        transportTwoRowMinimumWidth(stepperEndScale) <= width -> TransportForm.TWO_ROWS
        else -> TransportForm.STACKED
    }

    /** PATT and SONG segments, the hairline and ARR. */
    private val transportModeTrayWidth: Double
        get() = patternSegmentWidth * 2 + TRAY_DIVIDER_WIDTH + arrButtonWidth

    private fun transportStepperWidth(stepperEndScale: Double): Double =
        stepperEndWidth * stepperEndScale * 2 + STEPPER_READOUT_MIN_WIDTH

    /** Tracks share the width evenly while they fit; past that they take
     * [gridMinColumnWidth] and the row scrolls sideways. */
    fun gridColumnWidth(available: Double, tracks: Int, canAddTrack: Boolean): Double {
        val each = (available - gridRowReserved(tracks, canAddTrack)) / maxOf(tracks, 1)
        return maxOf(gridMinColumnWidth, each)
    }

    /** The full width one grid row draws at for a given column width. */
    fun gridRowWidth(columnWidth: Double, tracks: Int, canAddTrack: Boolean): Double =
        columnWidth * tracks + gridRowReserved(tracks, canAddTrack)

    /** The gutter, the add button, the 12 of padding and the 2 dp gaps. */
    private fun gridRowReserved(tracks: Int, canAddTrack: Boolean): Double {
        val items = 1 + tracks + (if (canAddTrack) 1 else 0)
        return gridGutterWidth + (if (canAddTrack) ADD_COLUMN_WIDTH else 0.0) + 12 + (items - 1) * 2.0
    }

    data class SideColumn(val width: Double, val octaves: Int)

    companion object {
        /** `Theme.trayHeight`. */
        const val THEME_TRAY_HEIGHT = 44.0

        /** The keyboard's horizontal inset and the gap between white keys. */
        const val KEYBOARD_HORIZONTAL_PADDING = 10.0
        const val WHITE_KEY_SPACING = 2.0

        const val SIDE_KEYBOARD_WIDTH = 400.0
        /** Fifteen 44 dp keys, fourteen 2 dp gaps and 20 dp of inset. */
        const val WIDE_SIDE_KEYBOARD_WIDTH = 708.0
        const val WIDE_SIDE_COLUMN_SLACK = 140.0

        const val ADD_COLUMN_WIDTH = 44.0
        const val CHROME_ROW_PADDING = 12.0
        const val CHROME_ROW_SPACING = 8.0
        const val PLAY_BUTTON_WIDTH = 56.0
        const val STEPPER_READOUT_MIN_WIDTH = 38.0
        const val TRANSPORT_TRAY_GAP = 0.0
        /** `TrayDivider.width`. */
        const val TRAY_DIVIDER_WIDTH = 1.0

        /** The fewest grid rows the fixed editor may show. */
        const val MINIMUM_GRID_ROWS = 4

        /** The layout is measured through the system bars but never through
         * the IME: raising the keyboard to type a name must not rebuild the
         * editor under the field. Nothing above the layout-deciding
         * `BoxWithConstraints` may apply `imePadding`. */
        const val MEASUREMENT_IGNORES_IME = true
        const val MEASUREMENT_IGNORES_SYSTEM_BARS = false

        val PHONE = ChipLayout(
            gridRowHeight = 40.0,
            gridMinColumnWidth = 70.0,
            gridGutterWidth = 28.0,
            trackHeaderHeight = 81.0,
            keyboardHeight = 110.0,
            keyboardMaxWidth = Double.POSITIVE_INFINITY,
            keyLabelSize = 9.0,
            chromeMaxWidth = Double.POSITIVE_INFINITY,
            trayHeight = THEME_TRAY_HEIGHT,
            stepperEndWidth = 38.0,
            historyButtonWidth = 34.0,
            titleIconTargetSize = 44.0,
            titleIconGlyphSize = 19.0,
            patternSegmentWidth = 52.0,
            arrButtonWidth = 48.0,
            patternChipWidth = 40.0,
            patternAddWidth = 42.0,
            isRegularWidth = false,
            sideColumnWidth = SIDE_KEYBOARD_WIDTH,
            keyboardOctaves = 1,
            usesSideKeyboard = false,
            chromeHeight = 158.0,
            stackedKeysHeight = 184.0,
        )

        val PAD = ChipLayout(
            gridRowHeight = 52.0,
            gridMinColumnWidth = 104.0,
            gridGutterWidth = 38.0,
            trackHeaderHeight = 96.0,
            keyboardHeight = 170.0,
            keyboardMaxWidth = 720.0,
            keyLabelSize = 11.0,
            chromeMaxWidth = 720.0,
            trayHeight = 52.0,
            stepperEndWidth = 48.0,
            historyButtonWidth = 44.0,
            titleIconTargetSize = 44.0,
            titleIconGlyphSize = 21.0,
            patternSegmentWidth = 60.0,
            arrButtonWidth = 56.0,
            patternChipWidth = 48.0,
            patternAddWidth = 48.0,
            isRegularWidth = true,
            sideColumnWidth = SIDE_KEYBOARD_WIDTH,
            keyboardOctaves = 1,
            usesSideKeyboard = false,
            chromeHeight = 174.0,
            stackedKeysHeight = 248.0,
        )

        /** What the grid needs beside the keyboard column before splitting is
         * worth it: gutter, four pad columns, the "+" and the padding. */
        val MINIMUM_SIDE_GRID_WIDTH: Double = PAD.gridGutterWidth + 4 * PAD.gridMinColumnWidth + 44 + 12

        /** Total window width at which the side arrangement becomes possible. */
        val MINIMUM_SIDE_BY_SIDE_WIDTH: Double = SIDE_KEYBOARD_WIDTH + MINIMUM_SIDE_GRID_WIDTH

        /** Width of one white key in a side column of [octaves] octaves. */
        fun whiteKeyWidth(columnWidth: Double, octaves: Int): Double =
            KeyboardGeometry(columnWidth - 2 * KEYBOARD_HORIZONTAL_PADDING, 7 * maxOf(octaves, 1) + 1).whiteWidth

        /** Two octaves only when the grid can spare the wider column plus slack
         * (1358 dp and up). */
        fun sideColumn(windowWidth: Double): SideColumn {
            val spare = windowWidth - MINIMUM_SIDE_GRID_WIDTH
            if (spare >= WIDE_SIDE_KEYBOARD_WIDTH + WIDE_SIDE_COLUMN_SLACK) return SideColumn(WIDE_SIDE_KEYBOARD_WIDTH, 2)
            return SideColumn(SIDE_KEYBOARD_WIDTH, 1)
        }
    }
}

/**
 * Where the keys land inside the keyboard, given the width inside its
 * horizontal padding. White keys share the width left after the 2 dp gaps;
 * each black key is centred on the gap between its two white neighbours.
 */
class KeyboardGeometry(insetWidth: Double, whiteKeys: Int) {
    val whiteWidth: Double
    val blackWidth: Double

    init {
        val keys = maxOf(whiteKeys, 1).toDouble()
        whiteWidth = (insetWidth - ChipLayout.WHITE_KEY_SPACING * (keys - 1)) / keys
        blackWidth = 0.58 * whiteWidth
    }

    /** Leading offset of the black key after white key [after] (zero-based). */
    fun blackKeyOffset(after: Int): Double {
        val spacing = ChipLayout.WHITE_KEY_SPACING
        val gapCenter = (after + 1) * (whiteWidth + spacing) - spacing / 2
        return gapCenter - blackWidth / 2
    }

    companion object {
        /** Semitone offsets of one octave's white keys, C up to B. */
        val WHITE_OFFSETS_IN_OCTAVE = listOf(0, 2, 4, 5, 7, 9, 11)

        /** One octave's black keys: semitone offset, and the white key it follows. */
        val BLACK_KEYS_IN_OCTAVE = listOf(1 to 0, 3 to 1, 6 to 3, 8 to 4, 10 to 5)

        /** White-key semitone offsets for [octaves] octaves plus the closing C. */
        fun whiteOffsets(octaves: Int): List<Int> {
            val count = maxOf(1, octaves)
            return (0 until count).flatMap { o -> WHITE_OFFSETS_IN_OCTAVE.map { it + o * 12 } } + (count * 12)
        }

        /** Black keys for [octaves] octaves: semitone offset to white-key index. */
        fun blackKeys(octaves: Int): List<Pair<Int, Int>> {
            val count = maxOf(1, octaves)
            return (0 until count).flatMap { o ->
                BLACK_KEYS_IN_OCTAVE.map { (offset, after) -> (offset + o * 12) to (after + o * WHITE_OFFSETS_IN_OCTAVE.size) }
            }
        }
    }
}

/** Picks the metrics for a window. The size class decides which numbers, the
 * proportions decide the arrangement. */
object LayoutResolver {
    fun resolve(size: WindowSize, sizeClass: SizeClass?): ChipLayout {
        var layout = if (sizeClass == SizeClass.REGULAR) arrangedPad(size) else ChipLayout.PHONE
        if (size.height - layout.editorFixedHeight < ChipLayout.MINIMUM_GRID_ROWS * (layout.gridRowHeight + 2)) {
            // Too short for the fixed editor in either arrangement: back to
            // stacked metrics, scrolled.
            layout = (if (sizeClass == SizeClass.REGULAR) ChipLayout.PAD else ChipLayout.PHONE).copy(scrollsEditor = true)
        }
        return layout
    }

    private fun arrangedPad(size: WindowSize): ChipLayout {
        val side = size.width > size.height && size.width >= ChipLayout.MINIMUM_SIDE_BY_SIDE_WIDTH
        if (!side) return ChipLayout.PAD
        val column = ChipLayout.sideColumn(size.width)
        return ChipLayout.PAD.copy(
            usesSideKeyboard = true,
            keyboardMaxWidth = Double.POSITIVE_INFINITY,
            keyboardHeight = 220.0,
            sideColumnWidth = column.width,
            keyboardOctaves = column.octaves,
        )
    }
}

/** How big a popover asks to be at a text [scale]: the ideal grows, the
 * minimum never does (a scaled floor outgrew a portrait tablet). */
object PopoverSizing {
    data class Frame(val minWidth: Double, val idealWidth: Double, val minHeight: Double, val idealHeight: Double)

    fun frame(minWidth: Double, idealWidth: Double, minHeight: Double, idealHeight: Double, scale: Double): Frame =
        Frame(minWidth, maxOf(idealWidth * scale, minWidth), minHeight, maxOf(idealHeight * scale, minHeight))

    /** The instrument editor's numbers, the defaults every popover started from. */
    val DEFAULT = Frame(380.0, 420.0, 420.0, 520.0)
}

/** Large text. iOS's accessibility Dynamic Type sizes are `fontScale >= 1.5`. */
object TextScale {
    const val ACCESSIBILITY_THRESHOLD = 1.5f

    /** Fixed-width chrome (grid, keys) stops growing its text here, as iOS
     * caps it at `accessibility1`. */
    const val FIXED_CHROME_CAP = 1.5f

    fun isAccessibilitySize(fontScale: Float): Boolean = fontScale >= ACCESSIBILITY_THRESHOLD

    fun capped(fontScale: Float): Float = minOf(fontScale, FIXED_CHROME_CAP)
}

/** The editor-level choices that combine the layout with the text size. */
object EditorChrome {
    /** Accessibility text makes the chrome several rows tall; a short window
     * leaves no grid. Either way the whole editor scrolls. */
    fun scrollsEditor(layout: ChipLayout, fontScale: Float): Boolean =
        TextScale.isAccessibilitySize(fontScale) || layout.scrollsEditor

    /** At accessibility sizes the transport always stacks; otherwise the
     * first form that fits [chromeWidth], with the stepper ends scaled. */
    fun transportForm(layout: ChipLayout, chromeWidth: Double, fontScale: Float): TransportForm =
        if (TextScale.isAccessibilitySize(fontScale)) {
            TransportForm.STACKED
        } else {
            layout.transportForm(chromeWidth, fontScale.toDouble())
        }

    fun patternBarStacks(fontScale: Float): Boolean = TextScale.isAccessibilitySize(fontScale)

    /** The scrolling editor's grid: 55% of the window, never under 360. */
    fun scrollingGridHeight(availableHeight: Double): Double = maxOf(360.0, availableHeight * 0.55)
}
