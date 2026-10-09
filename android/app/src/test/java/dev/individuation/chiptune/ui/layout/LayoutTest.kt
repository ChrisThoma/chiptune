package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.studio.ReviewPromptPolicy
import dev.individuation.chiptune.core.studio.ShareOutcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of `Tests/LayoutTests.swift`, all 43 cases: which metrics a window of
 * a given size and size class gets. The size class picks the numbers, the
 * proportions pick the arrangement. Sizes are dp, the iOS points one for one.
 */
class LayoutTest {
    /** iPad Pro 11-inch, the two ways round. */
    private val padPortrait = WindowSize(834.0, 1210.0)
    private val padLandscape = WindowSize(1210.0, 834.0)
    /** iPhone 15 Pro. */
    private val phonePortrait = WindowSize(393.0, 852.0)

    private fun resolve(size: WindowSize, sizeClass: SizeClass?) = LayoutResolver.resolve(size, sizeClass)
    private fun resolve(w: Double, h: Double, sizeClass: SizeClass?) = resolve(WindowSize(w, h), sizeClass)

    @Test fun compactWidthGetsPhoneMetricsWhateverTheSize() {
        assertEquals(ChipLayout.PHONE, resolve(phonePortrait, SizeClass.COMPACT))
        // A Split View slice is iPad-sized in one dimension and still compact.
        assertEquals(ChipLayout.PHONE, resolve(320.0, 1210.0, SizeClass.COMPACT))
    }

    /** No size class yet (before the first measure) falls back to the phone. */
    @Test fun unknownSizeClassFallsBackToPhone() {
        assertEquals(ChipLayout.PHONE, resolve(padLandscape, null))
    }

    @Test fun regularWidthGrowsTheGridAndKeys() {
        val layout = resolve(padPortrait, SizeClass.REGULAR)
        assertTrue(layout.gridRowHeight > ChipLayout.PHONE.gridRowHeight)
        assertTrue(layout.gridMinColumnWidth > ChipLayout.PHONE.gridMinColumnWidth)
        assertTrue(layout.keyboardHeight > ChipLayout.PHONE.keyboardHeight)
    }

    @Test fun portraitStacksAndCapsTheKeyboardWidth() {
        val layout = resolve(padPortrait, SizeClass.REGULAR)
        assertFalse(layout.usesSideKeyboard)
        assertTrue("Keys spread across the full width stop reading as a keyboard",
            layout.keyboardMaxWidth < padPortrait.width)
    }

    @Test fun landscapeMovesTheKeysBesideTheGrid() {
        val layout = resolve(padLandscape, SizeClass.REGULAR)
        assertTrue(layout.usesSideKeyboard)
        assertEquals(Double.POSITIVE_INFINITY, layout.keyboardMaxWidth, 0.0)
        assertTrue(layout.keyboardHeight > resolve(padPortrait, SizeClass.REGULAR).keyboardHeight)
    }

    @Test fun squareWindowStacks() {
        assertFalse(resolve(900.0, 900.0, SizeClass.REGULAR).usesSideKeyboard)
    }

    @Test fun sideKeyboardLeavesTheGridMostOfTheWindow() {
        val layout = resolve(padLandscape, SizeClass.REGULAR)
        val gridWidth = padLandscape.width - layout.sideColumnWidth
        assertTrue(gridWidth > padLandscape.width * 0.6)
    }

    @Test fun thirteenInchLandscapeGetsTwoOctavesInAWiderColumn() {
        for (size in listOf(WindowSize(1366.0, 1024.0), WindowSize(1376.0, 1032.0))) {
            val layout = resolve(size, SizeClass.REGULAR)
            assertTrue("${size.width} landscape should still split", layout.usesSideKeyboard)
            assertEquals("${size.width}", ChipLayout.WIDE_SIDE_KEYBOARD_WIDTH, layout.sideColumnWidth, 0.0)
            assertEquals("${size.width}", 2, layout.keyboardOctaves)
        }
    }

    @Test fun elevenInchLandscapeKeepsOneOctave() {
        for (size in listOf(WindowSize(1194.0, 834.0), WindowSize(1210.0, 834.0))) {
            val layout = resolve(size, SizeClass.REGULAR)
            assertTrue("${size.width} landscape should still split", layout.usesSideKeyboard)
            assertEquals("${size.width}", ChipLayout.SIDE_KEYBOARD_WIDTH, layout.sideColumnWidth, 0.0)
            assertEquals("${size.width}", 1, layout.keyboardOctaves)
        }
    }

    @Test fun halfWidthSplitViewStillStacks() {
        val layout = resolve(683.0, 1024.0, SizeClass.REGULAR)
        assertFalse(layout.usesSideKeyboard)
        assertEquals(1, layout.keyboardOctaves)
    }

    @Test fun theGridKeepsItsMinimumBesideEverySideColumn() {
        var width = 600.0
        while (width <= 2400.0) {
            val layout = resolve(width, 800.0, SizeClass.REGULAR)
            if (layout.usesSideKeyboard) {
                assertTrue("$width window squeezes the grid",
                    width - layout.sideColumnWidth >= ChipLayout.MINIMUM_SIDE_GRID_WIDTH)
            }
            width += 1.0
        }
    }

    @Test fun theSecondOctaveNeedsTheWiderColumnPlusSlack() {
        val boundary = ChipLayout.MINIMUM_SIDE_GRID_WIDTH +
            ChipLayout.WIDE_SIDE_KEYBOARD_WIDTH + ChipLayout.WIDE_SIDE_COLUMN_SLACK
        val wide = ChipLayout.sideColumn(boundary)
        assertEquals(ChipLayout.WIDE_SIDE_KEYBOARD_WIDTH, wide.width, 0.0)
        assertEquals(2, wide.octaves)
        val narrow = ChipLayout.sideColumn(boundary - 1)
        assertEquals(ChipLayout.SIDE_KEYBOARD_WIDTH, narrow.width, 0.0)
        assertEquals(1, narrow.octaves)
    }

    @Test fun shortWideWindowStacksRatherThanSqueezingTheGrid() {
        val squat = WindowSize(ChipLayout.MINIMUM_SIDE_BY_SIDE_WIDTH - 1, 700.0)
        assertTrue("This case only matters while the proportions say split", squat.width > squat.height)
        assertFalse(resolve(squat, SizeClass.REGULAR).usesSideKeyboard)
        val wideEnough = WindowSize(ChipLayout.MINIMUM_SIDE_BY_SIDE_WIDTH, 700.0)
        assertTrue(resolve(wideEnough, SizeClass.REGULAR).usesSideKeyboard)
    }

    /** The on-screen keyboard (IME) must not be measured through, or raising
     * it to type a song name flips the arrangement under the field. */
    @Test fun theOnScreenKeyboardCannotChangeTheArrangement() {
        assertTrue(ChipLayout.MEASUREMENT_IGNORES_IME)
        // The status and navigation bars still count: those are the window.
        assertFalse(ChipLayout.MEASUREMENT_IGNORES_SYSTEM_BARS)
        val window = WindowSize(1024.0, 1366.0)
        val throughKeyboard = WindowSize(1024.0, 940.0)
        assertFalse(resolve(window, SizeClass.REGULAR).usesSideKeyboard)
        assertTrue("If this ever stacks, the keyboard stops mattering here and the test can go",
            resolve(throughKeyboard, SizeClass.REGULAR).usesSideKeyboard)
    }

    @Test fun theArrangementIsAnAxisOfOneEditor() {
        assertEquals(EditorAxis.VERTICAL, resolve(padPortrait, SizeClass.REGULAR).editorAxis)
        assertEquals(EditorAxis.HORIZONTAL, resolve(padLandscape, SizeClass.REGULAR).editorAxis)
        assertEquals(EditorAxis.VERTICAL, resolve(phonePortrait, SizeClass.COMPACT).editorAxis)
        assertEquals(EditorAxis.VERTICAL,
            resolve(padLandscape, SizeClass.REGULAR).withoutDockedInstrumentEditor.editorAxis)
    }

    @Test fun shortWindowsScrollTheEditorRatherThanStarveTheGrid() {
        for (size in listOf(WindowSize(900.0, 600.0), WindowSize(1000.0, 500.0),
            WindowSize(1200.0, 400.0), WindowSize(700.0, 520.0))) {
            val layout = resolve(size, SizeClass.REGULAR)
            assertTrue("$size", layout.scrollsEditor)
            assertFalse("$size: the scrolling editor stacks, so nothing may think it's docked",
                layout.usesSideKeyboard)
        }
        assertTrue(resolve(400.0, 480.0, SizeClass.COMPACT).scrollsEditor)
    }

    @Test fun ordinaryWindowsKeepTheFixedEditor() {
        val windows = listOf(
            WindowSize(768.0, 1024.0) to SizeClass.REGULAR,
            WindowSize(1024.0, 1322.0) to SizeClass.REGULAR,
            WindowSize(1133.0, 700.0) to SizeClass.REGULAR,
            WindowSize(1376.0, 988.0) to SizeClass.REGULAR,
            WindowSize(683.0, 980.0) to SizeClass.REGULAR,
            WindowSize(375.0, 647.0) to SizeClass.COMPACT,
            WindowSize(402.0, 778.0) to SizeClass.COMPACT,
        )
        for ((size, sizeClass) in windows) assertFalse("$size", resolve(size, sizeClass).scrollsEditor)
    }

    @Test fun everyFixedEditorLeavesTheGridItsMinimumRows() {
        for (sizeClass in listOf(SizeClass.COMPACT, SizeClass.REGULAR)) {
            var width = 320.0
            while (width <= 1400.0) {
                var height = 300.0
                while (height <= 1400.0) {
                    val layout = resolve(width, height, sizeClass)
                    if (!layout.scrollsEditor) {
                        val grid = height - layout.editorFixedHeight
                        assertTrue("${width}x$height $sizeClass leaves the grid $grid",
                            grid / (layout.gridRowHeight + 2) >= ChipLayout.MINIMUM_GRID_ROWS)
                    }
                    height += 10.0
                }
                width += 20.0
            }
        }
    }

    @Test fun everyLandscapeIPadIsWideEnoughToSplit() {
        for (width in listOf(1194.0, 1366.0, 1180.0)) {
            assertTrue("$width landscape should still split", width > ChipLayout.MINIMUM_SIDE_BY_SIDE_WIDTH)
        }
    }

    @Test fun everyWhiteKeyIsAtLeast44WideInBothSideColumns() {
        for ((width, octaves) in listOf(ChipLayout.SIDE_KEYBOARD_WIDTH to 1, ChipLayout.WIDE_SIDE_KEYBOARD_WIDTH to 2)) {
            assertTrue("$octaves-octave column draws keys under 44",
                ChipLayout.whiteKeyWidth(width, octaves) >= 44.0)
        }
    }

    @Test fun theGridKeepsItsMinimumOnAThirteenInch() {
        val layout = resolve(1366.0, 1024.0, SizeClass.REGULAR)
        assertTrue(1366 - layout.sideColumnWidth >= ChipLayout.MINIMUM_SIDE_GRID_WIDTH)
    }

    // MARK: Grid column width

    @Test fun fourStarterTracksFitA375PhoneWithoutScrolling() {
        val song = Song.create("x")
        val layout = ChipLayout.PHONE
        val width = layout.gridColumnWidth(375.0, song.tracks.size, song.canAddTrack)
        assertTrue(width >= layout.gridMinColumnWidth)
        assertTrue(layout.gridRowWidth(width, song.tracks.size, song.canAddTrack) <= 375.0)
    }

    // MARK: Chrome tap targets

    @Test fun padChromeMetricsMeetTheFortyFourMinimum() {
        val pad = ChipLayout.PAD
        assertTrue(pad.trayHeight >= 44)
        assertTrue(pad.stepperEndWidth >= 44)
        assertTrue(pad.historyButtonWidth >= 44)
        assertTrue(pad.titleIconTargetSize >= 44)
        assertTrue(pad.patternChipWidth >= 48)
        assertTrue(pad.patternAddWidth >= 48)
    }

    @Test fun phoneChromeMetricsAreUnchanged() {
        val phone = ChipLayout.PHONE
        assertEquals(ChipLayout.THEME_TRAY_HEIGHT, phone.trayHeight, 0.0)
        assertEquals(38.0, phone.stepperEndWidth, 0.0)
        assertEquals(34.0, phone.historyButtonWidth, 0.0)
        assertEquals(44.0, phone.titleIconTargetSize, 0.0)
        assertEquals(19.0, phone.titleIconGlyphSize, 0.0)
        assertEquals(52.0, phone.patternSegmentWidth, 0.0)
        assertEquals(48.0, phone.arrButtonWidth, 0.0)
        assertEquals(40.0, phone.patternChipWidth, 0.0)
        assertEquals(42.0, phone.patternAddWidth, 0.0)
        assertEquals(70.0, phone.gridMinColumnWidth, 0.0)
    }

    @Test fun padTransportRowFitsAHalfWidthSplitView() {
        val pad = ChipLayout.PAD
        val total = 56 + (pad.patternSegmentWidth * 2 + pad.arrButtonWidth) + (pad.stepperEndWidth * 2 + 38) + (8 + 12)
        assertTrue(total <= 600)
    }

    @Test fun phoneTransportRowFitsA375Screen() {
        assertTrue(ChipLayout.PHONE.transportRowMinimumWidth() <= 375)
    }

    /** The stepper ends' growth at the largest non-accessibility text size. */
    private val xxxLargeStepperEndScale = 57.0 / 38.0

    @Test fun transportKeepsOneRowAtStandardTextOnTheSEAndProMax() {
        assertTrue(ChipLayout.PHONE.transportRowFits(375.0, 1.0))
        assertTrue(ChipLayout.PHONE.transportRowFits(440.0, 1.0))
        assertEquals(TransportForm.ROW, ChipLayout.PHONE.transportForm(375.0, 1.0))
        assertEquals(TransportForm.ROW, ChipLayout.PHONE.transportForm(440.0, 1.0))
    }

    @Test fun proMaxKeepsOneRowAtLargestStandardText() {
        assertEquals(TransportForm.ROW, ChipLayout.PHONE.transportForm(440.0, xxxLargeStepperEndScale))
    }

    @Test fun transportTakesTwoRowsWhenTheRowOverflowsAnSEAtLargestStandardText() {
        val phone = ChipLayout.PHONE
        assertTrue(phone.transportRowMinimumWidth(xxxLargeStepperEndScale) > 375)
        assertFalse(phone.transportRowFits(375.0, xxxLargeStepperEndScale))
        assertEquals(241.0, phone.transportTwoRowMinimumWidth(xxxLargeStepperEndScale), 1e-9)
        assertEquals(TransportForm.TWO_ROWS, phone.transportForm(375.0, xxxLargeStepperEndScale))
    }

    @Test fun compactIPadWindowTakesTwoTransportRows() {
        val slideOver = WindowSize(320.0, 1210.0)
        val layout = resolve(slideOver, SizeClass.COMPACT)
        assertEquals(ChipLayout.PHONE, layout)
        assertTrue(layout.transportRowMinimumWidth() > slideOver.width)
        assertFalse(layout.transportRowFits(slideOver.width, 1.0))
        assertTrue(layout.transportTwoRowMinimumWidth(1.0) <= slideOver.width)
        assertTrue(layout.transportTwoRowMinimumWidth(xxxLargeStepperEndScale) <= slideOver.width)
        assertEquals(TransportForm.TWO_ROWS, layout.transportForm(slideOver.width, 1.0))
        assertEquals(TransportForm.TWO_ROWS, layout.transportForm(slideOver.width, xxxLargeStepperEndScale))
    }

    @Test fun transportStacksOnlyWhenTwoRowsDontFit() {
        val phone = ChipLayout.PHONE
        val twoRows = phone.transportTwoRowMinimumWidth(xxxLargeStepperEndScale)
        assertEquals(TransportForm.TWO_ROWS, phone.transportForm(twoRows, xxxLargeStepperEndScale))
        assertEquals(TransportForm.STACKED, phone.transportForm(twoRows - 1, xxxLargeStepperEndScale))
        assertTrue(phone.transportStackMinimumWidth(xxxLargeStepperEndScale) <= twoRows - 1)
    }

    @Test fun chromeStopsSpreadingOnIPadAndNeverDoesOnIPhone() {
        val pad = resolve(padLandscape, SizeClass.REGULAR)
        assertTrue("Capped wider than the grid column is no cap at all",
            pad.chromeMaxWidth < padLandscape.width - ChipLayout.SIDE_KEYBOARD_WIDTH)
        assertEquals(Double.POSITIVE_INFINITY, ChipLayout.PHONE.chromeMaxWidth, 0.0)
    }

    @Test fun theInstrumentEditorGoesExactlyOnePlacePerLayout() {
        val landscape = resolve(padLandscape, SizeClass.REGULAR)
        assertTrue(landscape.docksInstrumentEditor)
        assertFalse(landscape.presentsInstrumentAsPopover)
        val portrait = resolve(padPortrait, SizeClass.REGULAR)
        assertFalse(portrait.docksInstrumentEditor)
        assertTrue(portrait.presentsInstrumentAsPopover)
        val phone = resolve(phonePortrait, SizeClass.COMPACT)
        assertFalse(phone.docksInstrumentEditor)
        assertFalse(phone.presentsInstrumentAsPopover)
    }

    @Test fun accessibilityStackMakesTheLandscapeInstrumentEditorReachable() {
        val landscape = resolve(padLandscape, SizeClass.REGULAR)
        assertTrue("precondition", landscape.docksInstrumentEditor)
        val stacked = landscape.withoutDockedInstrumentEditor
        assertFalse(stacked.docksInstrumentEditor)
        assertTrue(stacked.presentsInstrumentAsPopover)
    }

    // MARK: Review prompt (in LayoutTests on iOS too)

    @Test fun reviewRequestOnlyFiresForACompletedShare() {
        assertTrue(ReviewPromptPolicy.shouldRequest(true, ShareOutcome.COMPLETED))
        assertFalse(ReviewPromptPolicy.shouldRequest(true, ShareOutcome.CANCELED))
        assertFalse(ReviewPromptPolicy.shouldRequest(true, ShareOutcome.FAILED))
        assertFalse(ReviewPromptPolicy.shouldRequest(false, ShareOutcome.COMPLETED))
    }

    @Test fun cancelingOrFailingAShareLeavesTheMilestoneUnadvanced() {
        val canceled = ReviewPromptPolicy.afterShareDismiss(true, ShareOutcome.CANCELED, 5, 0)
        assertFalse(canceled.shouldRequestReview)
        assertEquals(0, canceled.lastRequestExportCount)
        val failed = ReviewPromptPolicy.afterShareDismiss(true, ShareOutcome.FAILED, 5, 0)
        assertFalse(failed.shouldRequestReview)
        assertEquals(0, failed.lastRequestExportCount)
        val completed = ReviewPromptPolicy.afterShareDismiss(true, ShareOutcome.COMPLETED, 5, 0)
        assertTrue(completed.shouldRequestReview)
        assertEquals(5, completed.lastRequestExportCount)
        val ineligible = ReviewPromptPolicy.afterShareDismiss(false, ShareOutcome.COMPLETED, 5, 2)
        assertFalse(ineligible.shouldRequestReview)
        assertEquals(2, ineligible.lastRequestExportCount)
    }

    @Test fun reviewRequestRetriesAtALaterExportMilestone() {
        assertFalse(ReviewPromptPolicy.isDue(2, 0))
        assertTrue(ReviewPromptPolicy.isDue(3, 0))
        assertFalse(ReviewPromptPolicy.isDue(12, 3))
        assertTrue(ReviewPromptPolicy.isDue(13, 3))
    }

    @Test fun capacityWarningAnnouncesOnlyOnThresholdCrossing() {
        assertTrue(ArrangementCapacityAnnouncement.shouldAnnounce(previouslyExceeded = false, nowExceeds = true))
        assertFalse(ArrangementCapacityAnnouncement.shouldAnnounce(previouslyExceeded = true, nowExceeds = true))
        assertFalse(ArrangementCapacityAnnouncement.shouldAnnounce(previouslyExceeded = true, nowExceeds = false))
    }

    // MARK: Export sheet accessibility

    @Test fun tailModeAdjustedMapping() {
        val seamless = ExportOptions.TailMode.SEAMLESS_LOOP
        val ringOut = ExportOptions.TailMode.RING_OUT
        assertEquals(ringOut, seamless.adjusted(AdjustmentDirection.INCREMENT))
        assertEquals(seamless, ringOut.adjusted(AdjustmentDirection.DECREMENT))
        assertEquals("no wrap at the far end", ringOut, ringOut.adjusted(AdjustmentDirection.INCREMENT))
        assertEquals("no wrap at the near end", seamless, seamless.adjusted(AdjustmentDirection.DECREMENT))
    }

    /** iOS checks its UIKit adjustable node; here the semantics actions go
     * through [Adjustable], which must forward both directions in order. */
    @Test fun adjustableForwardsBothDirectionsToItsClosure() {
        val seen = mutableListOf<AdjustmentDirection>()
        val adjustable = Adjustable { seen += it }
        adjustable.increment()
        adjustable.decrement()
        assertEquals(listOf(AdjustmentDirection.INCREMENT, AdjustmentDirection.DECREMENT), seen)
        assertEquals("Increment", Adjustable.INCREMENT_ACTION_NAME)
        assertEquals("Decrement", Adjustable.DECREMENT_ACTION_NAME)
    }

    // MARK: Keyboard geometry

    private val twoOctaveBlackKeyAfterIndices: List<Int> =
        (0 until 2).flatMap { octave -> listOf(0, 1, 3, 4, 5).map { it + 7 * octave } }

    @Test fun keyboardGeometryWhiteWidthMatchesTheColumnHelper() {
        for ((width, octaves) in listOf(ChipLayout.SIDE_KEYBOARD_WIDTH to 1, ChipLayout.WIDE_SIDE_KEYBOARD_WIDTH to 2)) {
            val inset = width - 2 * ChipLayout.KEYBOARD_HORIZONTAL_PADDING
            val geometry = KeyboardGeometry(inset, 7 * octaves + 1)
            assertEquals("$octaves-octave column disagrees with the view",
                ChipLayout.whiteKeyWidth(width, octaves), geometry.whiteWidth, 0.001)
        }
    }

    @Test fun everyBlackKeyIsCenteredOnTheGapBetweenItsWhiteNeighbors() {
        val whiteKeys = 15
        val inset = ChipLayout.WIDE_SIDE_KEYBOARD_WIDTH - 2 * ChipLayout.KEYBOARD_HORIZONTAL_PADDING
        val geometry = KeyboardGeometry(inset, whiteKeys)
        val spacing = ChipLayout.WHITE_KEY_SPACING
        for (after in twoOctaveBlackKeyAfterIndices) {
            val gapCenter = (after + 1) * (geometry.whiteWidth + spacing) - spacing / 2
            assertEquals("black key after white key $after is off its seam",
                gapCenter, geometry.blackKeyOffset(after) + geometry.blackWidth / 2, 0.001)
        }
        val topAfter = twoOctaveBlackKeyAfterIndices.last()
        val naiveWhiteWidth = inset / whiteKeys
        val naiveCenter = naiveWhiteWidth * (topAfter + 1) - naiveWhiteWidth * 0.29 + geometry.blackWidth / 2
        val trueCenter = (topAfter + 1) * (geometry.whiteWidth + spacing) - spacing / 2
        assertTrue("the spacing-blind formula should visibly drift by the top key",
            Math.abs(naiveCenter - trueCenter) > 1)
    }

    @Test fun theTopBlackKeyStaysInsideTheKeyboard() {
        val inset = ChipLayout.WIDE_SIDE_KEYBOARD_WIDTH - 2 * ChipLayout.KEYBOARD_HORIZONTAL_PADDING
        val geometry = KeyboardGeometry(inset, 15)
        val topAfter = twoOctaveBlackKeyAfterIndices.last()
        assertTrue("the top black key overhangs the keyboard",
            geometry.blackKeyOffset(topAfter) + geometry.blackWidth <= inset)
    }

    @Test fun popoverIdealGrowsButTheMinimumNeverDoes() {
        val ax5 = 3.1
        assertEquals(PopoverSizing.Frame(380.0, 420.0, 420.0, 520.0), PopoverSizing.frame(380.0, 420.0, 420.0, 520.0, 1.0))
        val frame = PopoverSizing.frame(380.0, 420.0, 420.0, 520.0, ax5)
        assertTrue(frame.minWidth < 834.0 / 2)
        assertTrue(frame.minHeight < 1210.0 / 2)
        assertEquals(420 * ax5, frame.idealWidth, 0.001)
        assertEquals(520 * ax5, frame.idealHeight, 0.001)
        val small = PopoverSizing.frame(380.0, 400.0, 420.0, 430.0, 0.8)
        assertTrue(small.idealWidth >= small.minWidth)
        assertTrue(small.idealHeight >= small.minHeight)
    }
}
