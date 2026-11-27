#if os(macOS)
import SwiftUI
import XCTest
@testable import Chiptune

/// The Mac window's sizes against `ChipLayout`. A Mac window is always laid
/// out like a landscape iPad: grid on the left, keys and the docked sound
/// controls in a column on the right. The minimum size is what guarantees
/// that, so it is pinned here rather than found by dragging a corner.
final class MacWindowLayoutTests: XCTestCase {

    func testTheMacIsAlwaysRegularWidth() {
        XCTAssertEqual(MacWindow.sizeClass, .regular)
        XCTAssertTrue(MacWindow.layout(for: MacWindow.minimumSize).isRegularWidth)
    }

    /// Dragged as small as it goes, the window still puts the keys beside
    /// the grid, and never falls back to the scrolling editor.
    func testTheMinimumSizeKeepsTheSideLayout() {
        let layout = MacWindow.layout(for: MacWindow.minimumSize)
        XCTAssertTrue(layout.usesSideKeyboard)
        XCTAssertTrue(layout.docksInstrumentEditor)
        XCTAssertFalse(layout.scrollsEditor)
        XCTAssertGreaterThanOrEqual(MacWindow.minimumSize.width, ChipLayout.minimumSideBySideWidth)
    }

    /// The minimum is tall enough for a useful part, not just for the
    /// threshold: eight rows, half a 16-step pattern.
    func testTheMinimumSizeShowsAtLeastEightRows() {
        let layout = MacWindow.layout(for: MacWindow.minimumSize)
        let rows = (MacWindow.minimumSize.height - layout.editorFixedHeight) / (layout.gridRowHeight + 2)
        XCTAssertGreaterThanOrEqual(rows, 8)
    }

    /// The window opens a little larger than the minimum, with one octave.
    func testTheDefaultSizeIsSideBySideAndAtLeastTheMinimum() {
        let layout = MacWindow.layout(for: MacWindow.defaultSize)
        XCTAssertTrue(layout.usesSideKeyboard)
        XCTAssertFalse(layout.scrollsEditor)
        XCTAssertGreaterThanOrEqual(MacWindow.defaultSize.width, MacWindow.minimumSize.width)
        XCTAssertGreaterThanOrEqual(MacWindow.defaultSize.height, MacWindow.minimumSize.height)
    }

    /// A big window (a 27-inch display, maximized) earns the two-octave
    /// column, the same rule as a 13-inch iPad.
    func testALargeWindowGetsTwoOctaves() {
        let layout = MacWindow.layout(for: CGSize(width: 1800, height: 1100))
        XCTAssertTrue(layout.usesSideKeyboard)
        XCTAssertEqual(layout.keyboardOctaves, 2)
        XCTAssertEqual(layout.sideColumnWidth, ChipLayout.wideSideKeyboardWidth)
    }

    /// The Mac has no fold, so the size alone decides.
    func testLayoutIsResolveAtRegularWidthWithNoFold() {
        for size in [MacWindow.minimumSize, MacWindow.defaultSize, CGSize(width: 1500, height: 900)] {
            XCTAssertEqual(MacWindow.layout(for: size),
                           ChipLayout.resolve(size: size, horizontalSizeClass: .regular))
        }
    }
}
#endif
