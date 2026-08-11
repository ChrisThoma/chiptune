import XCTest
import SwiftUI
@testable import Chiptune

/// Which metrics a window of a given size and size class gets.
///
/// The rule this pins down is that neither input decides on its own: the size
/// class picks the numbers, and the proportions pick the arrangement. Getting
/// that wrong is invisible on the device you happened to test on and obvious
/// on every other one — an iPad in a narrow Split View slice drawn with
/// iPad-sized cells, or a portrait iPad with the keyboard in a side column
/// that leaves the grid a sliver.
final class LayoutTests: XCTestCase {

    /// iPad Pro 11-inch, the two ways round.
    private let padPortrait = CGSize(width: 834, height: 1210)
    private let padLandscape = CGSize(width: 1210, height: 834)
    /// iPhone 15 Pro.
    private let phonePortrait = CGSize(width: 393, height: 852)

    func testCompactWidthGetsPhoneMetricsWhateverTheSize() {
        XCTAssertEqual(ChipLayout.resolve(size: phonePortrait, horizontalSizeClass: .compact),
                       .phone)
        // A Split View slice is iPad-sized in one dimension and still compact.
        XCTAssertEqual(ChipLayout.resolve(size: CGSize(width: 320, height: 1210),
                                          horizontalSizeClass: .compact),
                       .phone)
    }

    /// SwiftUI hands back a nil size class before the first layout pass.
    func testUnknownSizeClassFallsBackToPhone() {
        XCTAssertEqual(ChipLayout.resolve(size: padLandscape, horizontalSizeClass: nil), .phone)
    }

    func testRegularWidthGrowsTheGridAndKeys() {
        let layout = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertGreaterThan(layout.gridRowHeight, ChipLayout.phone.gridRowHeight)
        XCTAssertGreaterThan(layout.gridMinColumnWidth, ChipLayout.phone.gridMinColumnWidth)
        XCTAssertGreaterThan(layout.keyboardHeight, ChipLayout.phone.keyboardHeight)
    }

    func testPortraitStacksAndCapsTheKeyboardWidth() {
        let layout = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertFalse(layout.usesSideKeyboard)
        XCTAssertLessThan(layout.keyboardMaxWidth, padPortrait.width,
                          "Keys spread across the full width stop reading as a keyboard")
    }

    func testLandscapeMovesTheKeysBesideTheGrid() {
        let layout = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(layout.usesSideKeyboard)
        // The column is the cap in this arrangement, so the keys fill it.
        XCTAssertEqual(layout.keyboardMaxWidth, .infinity)
        XCTAssertGreaterThan(layout.keyboardHeight,
                             ChipLayout.resolve(size: padPortrait,
                                                horizontalSizeClass: .regular).keyboardHeight)
    }

    /// A square-ish window is the boundary between the two arrangements, and
    /// the tie has to break somewhere: equal sides stack rather than split,
    /// so the grid keeps the full width.
    func testSquareWindowStacks() {
        let layout = ChipLayout.resolve(size: CGSize(width: 900, height: 900),
                                        horizontalSizeClass: .regular)
        XCTAssertFalse(layout.usesSideKeyboard)
    }

    /// The grid has to fit beside the keyboard column with room to spare, or
    /// the side arrangement is worse than the stacked one it replaces.
    func testSideKeyboardLeavesTheGridMostOfTheWindow() {
        let gridWidth = padLandscape.width - ChipLayout.sideKeyboardWidth
        XCTAssertGreaterThan(gridWidth, padLandscape.width * 0.6)
    }
}
