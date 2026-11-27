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

    /// In the one-octave band the eight white keys keep the width they have
    /// at the two-octave threshold instead of stretching across the window,
    /// and sit centred under the full-width control row.
    func testOneOctaveIsCappedAtTheThresholdKeyWidthAndCentred() {
        for width in [MacWindow.minimumSize.width, 1000, MacWindow.twoOctaveMinimumWidth - 1] {
            let size = CGSize(width: width, height: 900)
            let keys = MacWindow.keysFrame(in: size)
            let geometry = ChipLayout.KeyboardGeometry(insetWidth: keys.width, whiteKeys: 8)
            XCTAssertEqual(geometry.whiteWidth, MacWindow.minimumWhiteKeyWidth, accuracy: 0.001, "\(width)")
            XCTAssertEqual(keys.midX, width / 2, accuracy: 0.001, "\(width)")
            XCTAssertEqual(keys.height, MacWindow.keyHeight, "\(width)")
            XCTAssertEqual(keys.maxY, MacWindow.keyboardFrame(in: size).maxY - 10, "\(width)")
        }
    }

    /// Two octaves run the full width, less the keyboard's inset.
    func testTwoOctavesRunTheFullWidth() {
        for width in [MacWindow.twoOctaveMinimumWidth, MacWindow.defaultSize.width, wide.width] {
            let keys = MacWindow.keysFrame(in: CGSize(width: width, height: 900))
            XCTAssertEqual(keys.minX, ChipLayout.keyboardHorizontalPadding, "\(width)")
            XCTAssertEqual(keys.width, width - 2 * ChipLayout.keyboardHorizontalPadding, "\(width)")
        }
    }

    // MARK: Track columns

    /// A track column is one width at every window size and track count:
    /// a wider window adds empty background after the + column, not wider
    /// tracks.
    func testTrackColumnsKeepOneWidthWhateverTheWindow() {
        for width in [MacWindow.minimumSize.width, 1000, MacWindow.defaultSize.width, 1800, 2400] {
            let size = CGSize(width: width, height: 900)
            let layout = MacWindow.layout(for: size)
            let available = width - MacWindow.soundColumnWidth - layout.sideGapWidth
            for tracks in [1, 4, 8] {
                XCTAssertEqual(layout.gridColumnWidth(available: available, tracks: tracks,
                                                      canAddTrack: tracks < 8),
                               MacWindow.trackColumnWidth, "\(width)pt, \(tracks) tracks")
            }
        }
    }

    func testTheGridDoesNotGrowWithTheWindow() {
        func rowWidth(_ width: CGFloat) -> CGFloat {
            let layout = MacWindow.layout(for: CGSize(width: width, height: 900))
            let column = layout.gridColumnWidth(available: width - MacWindow.soundColumnWidth - 1,
                                                tracks: 4, canAddTrack: true)
            return layout.gridRowWidth(columnWidth: column, tracks: 4, canAddTrack: true)
        }
        XCTAssertEqual(rowWidth(MacWindow.defaultSize.width), rowWidth(1800))
        XCTAssertEqual(rowWidth(1800), rowWidth(2400))
    }

    /// The starter song's four tracks fit beside the sound column at the
    /// minimum width, so the smallest window doesn't open scrolled sideways.
    func testFourTracksFitAtTheMinimumWidth() {
        let layout = MacWindow.layout(for: MacWindow.minimumSize)
        let row = layout.gridRowWidth(columnWidth: MacWindow.trackColumnWidth, tracks: 4, canAddTrack: true)
        XCTAssertLessThanOrEqual(row, MacWindow.minimumSize.width - MacWindow.soundColumnWidth - layout.sideGapWidth)
    }

    /// The widest cell label, a sharp in the top octave with an effect mark,
    /// fits at full size.
    func testAMarkedNoteFitsUnshrunk() {
        let available = MacWindow.trackColumnWidth - EffectMark.cellPadding
        XCTAssertEqual(EffectMark.fitScale(name: "C#5", effect: .bendIn, fontSize: 12, available: available), 1)
        XCTAssertGreaterThanOrEqual(MacWindow.trackColumnWidth, 70, "never narrower than the phone's floor")
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
