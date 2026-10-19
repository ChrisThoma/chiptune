import XCTest
import SwiftUI
@testable import Chiptune

/// `popoverSized` used to scale the popover's *minimum* with Dynamic Type, so
/// at AX3–AX5 (2.3–3.1×) a 380×420 floor became 890–1180 wide: wider than an
/// 834pt portrait iPad, and the content was clipped.
final class PopoverSizingTests: XCTestCase {

    /// AX5, the largest accessibility size.
    private let ax5: CGFloat = 3.1
    /// iPad Pro 11-inch portrait, the narrowest regular-width full window.
    private let portraitWidth: CGFloat = 834
    private let portraitHeight: CGFloat = 1210

    func testDefaultTextSizeIsUnchanged() {
        let frame = PopoverSizing.frame(minWidth: 380, idealWidth: 420,
                                        minHeight: 420, idealHeight: 520, scale: 1)
        XCTAssertEqual(frame, PopoverSizing.Frame(minWidth: 380, idealWidth: 420,
                                                  minHeight: 420, idealHeight: 520))
    }

    func testMinimumNeverOutgrowsAPortraitIPadAtAccessibilitySizes() {
        for (minW, idealW, minH, idealH) in [(380.0, 420.0, 420.0, 520.0),   // instrument, export
                                             (380.0, 420.0, 420.0, 560.0)] { // arrangement
            let frame = PopoverSizing.frame(minWidth: minW, idealWidth: idealW,
                                            minHeight: minH, idealHeight: idealH, scale: ax5)
            XCTAssertLessThan(frame.minWidth, portraitWidth / 2)
            XCTAssertLessThan(frame.minHeight, portraitHeight / 2)
        }
    }

    /// The ideal still grows, so the system gives the popover as much room as
    /// the window allows rather than the default-size box.
    func testIdealStillGrowsWithTheTextSize() {
        let frame = PopoverSizing.frame(minWidth: 380, idealWidth: 420,
                                        minHeight: 420, idealHeight: 520, scale: ax5)
        XCTAssertEqual(frame.idealWidth, 420 * ax5, accuracy: 0.001)
        XCTAssertEqual(frame.idealHeight, 520 * ax5, accuracy: 0.001)
    }

    /// Below the default size (xSmall scales under 1) the ideal must not sink
    /// under the minimum.
    func testIdealNeverSinksBelowTheMinimum() {
        let frame = PopoverSizing.frame(minWidth: 380, idealWidth: 400,
                                        minHeight: 420, idealHeight: 430, scale: 0.8)
        XCTAssertGreaterThanOrEqual(frame.idealWidth, frame.minWidth)
        XCTAssertGreaterThanOrEqual(frame.idealHeight, frame.minHeight)
    }
}

/// The export popover's height follows the format: a MIDI export has no
/// repeats or ending, so the WAV height left a block of empty space under it.
final class ExportPopoverSizeTests: XCTestCase {

    /// Measured on a 13-inch iPad at the default text size: the WAV form
    /// runs to about 530pt, the MIDI one to about 280pt.
    func testWavIsTallEnoughForItsExportButton() {
        XCTAssertGreaterThanOrEqual(ExportPopoverSize.heights(for: .wav).ideal, 560)
    }

    /// Repeats and Style stack under the format picker, so a video needs
    /// at least the room a WAV's Repeats and Ending do.
    func testVideoIsTallEnoughForRepeatsAndStyle() {
        XCTAssertGreaterThanOrEqual(ExportPopoverSize.heights(for: .video).ideal, 580)
    }

    func testMidiLeavesNoBigEmptyBlock() {
        let midi = ExportPopoverSize.heights(for: .midi)
        XCTAssertLessThanOrEqual(midi.ideal, 360)
        XCTAssertLessThanOrEqual(midi.min, midi.ideal)
    }

    func testTheMinimumNeverExceedsTheIdeal() {
        for format in ExportOptions.Format.allCases {
            let heights = ExportPopoverSize.heights(for: format)
            XCTAssertLessThanOrEqual(heights.min, heights.ideal, "\(format)")
        }
    }
}
