#if os(macOS)
import SwiftUI
import XCTest
@testable import Chiptune

/// The Mac window's layout: grid top left, the selected track's sound
/// controls in a column to its right, and a piano across the whole bottom of
/// the window, two octaves whenever the window is wide enough for them.
/// Pinned here rather than found by dragging a corner.
final class MacWindowLayoutTests: XCTestCase {

    private let wide = CGSize(width: 1800, height: 1100)

    func testTheMacIsAlwaysRegularWidth() {
        XCTAssertEqual(MacWindow.sizeClass, .regular)
        XCTAssertTrue(MacWindow.layout(for: MacWindow.minimumSize).isRegularWidth)
    }

    /// Every size gets the same arrangement: the keys along the bottom and
    /// the sound controls docked beside the grid, never the scrolling editor.
    func testEverySizeHasTheKeysAlongTheBottomAndTheSoundControlsDocked() {
        for size in [MacWindow.minimumSize, MacWindow.defaultSize, wide] {
            let layout = MacWindow.layout(for: size)
            XCTAssertTrue(layout.keysAlongBottom, "\(size)")
            XCTAssertTrue(layout.docksInstrumentEditor, "\(size)")
            XCTAssertFalse(layout.scrollsEditor, "\(size)")
            XCTAssertEqual(layout.sideColumnWidth, MacWindow.soundColumnWidth, "\(size)")
        }
    }

    func testTheKeysAreInstrumentSized() {
        XCTAssertEqual(MacWindow.layout(for: MacWindow.defaultSize).keyboardHeight, MacWindow.keyHeight)
        XCTAssertGreaterThanOrEqual(MacWindow.keyHeight, 170)
        XCTAssertLessThanOrEqual(MacWindow.keyHeight, 220)
    }

    /// The keyboard runs the full width of the window and sits at its bottom
    /// edge; nothing is beside it or under it.
    func testTheKeyboardSpansTheWholeBottomOfTheWindow() {
        for size in [MacWindow.minimumSize, MacWindow.defaultSize, wide] {
            let frame = MacWindow.keyboardFrame(in: size)
            XCTAssertEqual(frame.minX, 0, "\(size)")
            XCTAssertEqual(frame.width, size.width, "\(size)")
            XCTAssertEqual(frame.maxY, size.height, "\(size)")
            XCTAssertEqual(frame.height, MacWindow.bottomKeysHeight, "\(size)")
        }
    }

    // MARK: Octaves

    /// Two octaves (C to C, fifteen white keys) once each white key gets at
    /// least `minimumWhiteKeyWidth`, by the same geometry KeyboardView draws.
    func testTwoOctavesStartWhereAWhiteKeyReachesTheMinimumWidth() {
        let threshold = MacWindow.twoOctaveMinimumWidth
        let inset = threshold - 2 * ChipLayout.keyboardHorizontalPadding
        let keys = ChipLayout.KeyboardGeometry(insetWidth: inset, whiteKeys: 15)
        XCTAssertEqual(keys.whiteWidth, MacWindow.minimumWhiteKeyWidth, accuracy: 0.001)

        XCTAssertEqual(MacWindow.layout(for: CGSize(width: threshold, height: 900)).keyboardOctaves, 2)
        XCTAssertEqual(MacWindow.layout(for: CGSize(width: threshold - 1, height: 900)).keyboardOctaves, 1)
    }

    func testTheDefaultAndAWideWindowShowTwoOctaves() {
        XCTAssertEqual(MacWindow.layout(for: MacWindow.defaultSize).keyboardOctaves, 2)
        XCTAssertEqual(MacWindow.layout(for: wide).keyboardOctaves, 2)
    }

    /// The narrowest windows show one octave at the same key height.
    func testANarrowWindowShowsOneOctaveAtTheSameHeight() {
        let narrow = MacWindow.layout(for: MacWindow.minimumSize)
        XCTAssertLessThan(MacWindow.minimumSize.width, MacWindow.twoOctaveMinimumWidth)
        XCTAssertEqual(narrow.keyboardOctaves, 1)
        XCTAssertEqual(narrow.keyboardHeight, MacWindow.keyHeight)
    }

    // MARK: Grid room

    /// Dragged as small as it goes, the window still shows six grid rows
    /// above the keyboard, and the grid gets the side-by-side width it needs.
    func testTheMinimumSizeShowsAtLeastSixRows() {
        XCTAssertGreaterThanOrEqual(MacWindow.gridRows(in: MacWindow.minimumSize), 6)
        XCTAssertGreaterThanOrEqual(MacWindow.minimumSize.width, ChipLayout.minimumSideBySideWidth)
    }

    func testTheDefaultSizeIsAtLeastTheMinimum() {
        XCTAssertGreaterThanOrEqual(MacWindow.defaultSize.width, MacWindow.minimumSize.width)
        XCTAssertGreaterThanOrEqual(MacWindow.defaultSize.height, MacWindow.minimumSize.height)
        XCTAssertGreaterThan(MacWindow.gridRows(in: MacWindow.defaultSize),
                             MacWindow.gridRows(in: MacWindow.minimumSize))
    }
}
#endif
