package dev.individuation.chiptune.ui.layout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which container each screen opens in for a window (iOS: `.sheet`, a
 * `.popover` that adapts to a sheet when compact, or the docked column), and
 * where an anchored popover lands.
 */
class SurfacePresentationTest {
    private val phone = LayoutResolver.resolve(WindowSize(393.0, 800.0), SizeClass.COMPACT)
    private val portraitPad = LayoutResolver.resolve(WindowSize(800.0, 1232.0), SizeClass.REGULAR)
    private val landscapePad = LayoutResolver.resolve(WindowSize(1280.0, 752.0), SizeClass.REGULAR)

    @Test fun thePhoneKeepsItsSheets() {
        for (kind in SurfaceKind.entries) {
            assertEquals("$kind", SurfaceContainer.SHEET, SurfaceContainers.container(kind, phone))
        }
    }

    @Test fun aPortraitTabletAnchorsPopoversAndCentresTheLibrary() {
        assertEquals(SurfaceContainer.POPOVER, SurfaceContainers.container(SurfaceKind.INSTRUMENT_EDITOR, portraitPad))
        assertEquals(SurfaceContainer.POPOVER, SurfaceContainers.container(SurfaceKind.ARRANGEMENT, portraitPad))
        assertEquals(SurfaceContainer.POPOVER, SurfaceContainers.container(SurfaceKind.EXPORT, portraitPad))
        assertEquals(SurfaceContainer.POPOVER, SurfaceContainers.container(SurfaceKind.KEYBOARD_HELP, portraitPad))
        assertEquals(SurfaceContainer.DIALOG, SurfaceContainers.container(SurfaceKind.SONGS, portraitPad))
    }

    @Test fun theSideLayoutDocksTheInstrumentEditor() {
        assertTrue(landscapePad.usesSideKeyboard)
        assertEquals(SurfaceContainer.DOCKED, SurfaceContainers.container(SurfaceKind.INSTRUMENT_EDITOR, landscapePad))
        assertEquals(SurfaceContainer.POPOVER, SurfaceContainers.container(SurfaceKind.ARRANGEMENT, landscapePad))
        assertEquals(SurfaceContainer.DIALOG, SurfaceContainers.container(SurfaceKind.SONGS, landscapePad))
    }

    /** The scrolling editor stacks, so the selected track opens a popover. */
    @Test fun theScrollingEditorNeverDocks() {
        val stacked = landscapePad.withoutDockedInstrumentEditor
        assertEquals(SurfaceContainer.POPOVER, SurfaceContainers.container(SurfaceKind.INSTRUMENT_EDITOR, stacked))
    }

    @Test fun popoverSizesFollowIos() {
        assertEquals(PopoverSizing.DEFAULT, SurfaceContainers.popover(SurfaceKind.INSTRUMENT_EDITOR, 1.0).frame)
        assertEquals(PopoverSizing.DEFAULT, SurfaceContainers.popover(SurfaceKind.EXPORT, 1.0).frame)
        assertEquals(560.0, SurfaceContainers.popover(SurfaceKind.ARRANGEMENT, 1.0).frame.idealHeight, 0.0)
        assertFalse(SurfaceContainers.popover(SurfaceKind.ARRANGEMENT, 1.0).wrapsHeight)
        val help = SurfaceContainers.popover(SurfaceKind.KEYBOARD_HELP, 1.0)
        assertEquals(320.0, help.frame.idealWidth, 0.0)
        assertTrue(help.wrapsHeight)
        // Large text grows the ideal, never the floor.
        val big = SurfaceContainers.popover(SurfaceKind.INSTRUMENT_EDITOR, 2.0).frame
        assertEquals(840.0, big.idealWidth, 0.0)
        assertEquals(380.0, big.minWidth, 0.0)
    }

    @Test fun theLibraryDialogIsCappedAt640() {
        assertEquals(640.0, SurfaceContainers.libraryDialogWidth(1280.0), 0.0)
        assertEquals(600.0 - 2 * PopoverPlacement.MARGIN, SurfaceContainers.libraryDialogWidth(600.0), 0.0)
    }

    // MARK: Placement

    private val window = PopoverPlacement.Bounds(0.0, 0.0, 800.0, 1232.0)
    private val m = PopoverPlacement.MARGIN
    private val g = PopoverPlacement.GAP

    @Test fun belowTheAnchorAtItsIdealSize() {
        val header = PopoverPlacement.Bounds(300.0, 250.0, 400.0, 346.0)
        val p = PopoverPlacement.place(header, PopoverSizing.DEFAULT, wrapsHeight = false, window = window)
        assertEquals(420.0, p.width, 0.0)
        assertEquals(520.0, p.height, 0.0)
        assertEquals(350.0 - 210.0, p.x, 0.0)
        assertEquals(346.0 + g, p.y, 0.0)
        assertTrue(p.below)
    }

    @Test fun keptInsideTheWindowSideways() {
        val leftHeader = PopoverPlacement.Bounds(40.0, 250.0, 140.0, 346.0)
        assertEquals(m, PopoverPlacement.place(leftHeader, PopoverSizing.DEFAULT, false, window).x, 0.0)
        val menu = PopoverPlacement.Bounds(740.0, 10.0, 784.0, 54.0)
        val p = PopoverPlacement.place(menu, PopoverSizing.DEFAULT, false, window)
        assertEquals(800.0 - m - 420.0, p.x, 0.0)
    }

    @Test fun aboveWhenThereIsMoreRoomThere() {
        val low = PopoverPlacement.Bounds(300.0, 1000.0, 400.0, 1050.0)
        val p = PopoverPlacement.place(low, PopoverSizing.DEFAULT, false, window)
        assertFalse(p.below)
        assertEquals(520.0, p.height, 0.0)
        assertEquals(1000.0 - g - 520.0, p.y, 0.0)
    }

    @Test fun shortOfRoomItShrinksButNotBelowTheMinimum() {
        val short = PopoverPlacement.Bounds(0.0, 0.0, 1280.0, 752.0)
        val arr = PopoverPlacement.Bounds(300.0, 200.0, 356.0, 252.0)
        val frame = SurfaceContainers.popover(SurfaceKind.ARRANGEMENT, 1.0).frame
        val p = PopoverPlacement.place(arr, frame, false, short)
        assertTrue(p.below)
        assertEquals(752.0 - m - (252.0 + g), p.height, 0.0)
        // Even less room: the floor holds and the box slides up to fit.
        val lower = PopoverPlacement.Bounds(300.0, 330.0, 356.0, 382.0)
        val q = PopoverPlacement.place(lower, frame, false, PopoverPlacement.Bounds(0.0, 0.0, 1280.0, 752.0))
        assertTrue(q.height >= frame.minHeight)
        assertTrue(q.y + q.height <= 752.0 - m)
        assertTrue(q.y >= m)
    }

    @Test fun aNarrowWindowNarrowsThePopover() {
        val narrow = PopoverPlacement.Bounds(0.0, 0.0, 360.0, 800.0)
        val p = PopoverPlacement.place(PopoverPlacement.Bounds(10.0, 10.0, 50.0, 50.0), PopoverSizing.DEFAULT, false, narrow)
        assertEquals(360.0 - 2 * m, p.width, 0.0)
        assertEquals(m, p.x, 0.0)
    }

    @Test fun aWrappingPopoverGetsTheRoomAsACap() {
        val menu = PopoverPlacement.Bounds(740.0, 10.0, 784.0, 54.0)
        val help = SurfaceContainers.popover(SurfaceKind.KEYBOARD_HELP, 1.0)
        val p = PopoverPlacement.place(menu, help.frame, true, window)
        assertEquals(320.0, p.width, 0.0)
        assertEquals(1232.0 - m - (54.0 + g), p.height, 0.0)
        // Its real height arrives once measured; the origin follows it.
        assertEquals(54.0 + g, PopoverPlacement.origin(menu, 320.0, 400.0, window).second, 0.0)
    }

    @Test fun noAnchorCentresIt() {
        val p = PopoverPlacement.place(null, PopoverSizing.DEFAULT, false, window)
        assertEquals((800.0 - 420.0) / 2, p.x, 0.0)
        assertEquals((1232.0 - 520.0) / 2, p.y, 0.0)
    }
}
