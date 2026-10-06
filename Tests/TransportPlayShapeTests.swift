import XCTest
import SwiftUI
@testable import Chiptune

/// At accessibility sizes the stacked transport kept Play 56pt wide while its
/// height grew with the text, under an 18pt glyph that never grew: a tall thin
/// pill with a speck in it.
final class TransportPlayShapeTests: XCTestCase {

    private let ax3: CGFloat = 2.3

    func testDefaultSizeKeepsTheFixedWidthAndGlyph() {
        XCTAssertEqual(TransportPlayShape.width(fillsRow: false), ChipLayout.playButtonWidth)
        XCTAssertEqual(TransportPlayShape.glyphSize(scale: 1), 18)
    }

    /// Stacked, Play has a row to itself, so it takes all of it.
    func testStackedPlayFillsItsRow() {
        XCTAssertNil(TransportPlayShape.width(fillsRow: true))
    }

    func testGlyphGrowsWithTheText() {
        XCTAssertEqual(TransportPlayShape.glyphSize(scale: ax3), 18 * ax3, accuracy: 0.001)
    }
}
