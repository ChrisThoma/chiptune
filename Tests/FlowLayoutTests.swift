import XCTest
@testable import Chiptune

/// The wrapping row behind the sound panel's preset chips. The panel is a
/// sheet on a phone and a narrow docked column on a landscape iPad, so the
/// chips have to break onto new lines rather than run off the edge.
final class FlowLayoutTests: XCTestCase {

    private func sizes(_ widths: [CGFloat]) -> [CGSize] {
        widths.map { CGSize(width: $0, height: 44) }
    }

    func testEverythingThatFitsStaysOnOneLine() {
        XCTAssertEqual(FlowLayout.lines(for: sizes([50, 50, 50]), width: 200, spacing: 8),
                       [[0, 1, 2]])
    }

    func testAChipThatWouldOverflowStartsTheNextLine() {
        // 60 + 8 + 60 + 8 + 60 = 196 > 150.
        XCTAssertEqual(FlowLayout.lines(for: sizes([60, 60, 60]), width: 150, spacing: 8),
                       [[0, 1], [2]])
    }

    /// Exactly filling the width is a fit, not an overflow.
    func testAnExactFitDoesNotWrap() {
        XCTAssertEqual(FlowLayout.lines(for: sizes([46, 46]), width: 100, spacing: 8),
                       [[0, 1]])
    }

    /// A chip wider than the column still gets a line of its own rather than
    /// vanishing or looping forever.
    func testAChipWiderThanTheLineGetsItsOwnLine() {
        XCTAssertEqual(FlowLayout.lines(for: sizes([40, 300, 40]), width: 100, spacing: 8),
                       [[0], [1], [2]])
    }

    func testNoChipsMeansNoLines() {
        XCTAssertEqual(FlowLayout.lines(for: [], width: 100, spacing: 8), [])
    }
}
