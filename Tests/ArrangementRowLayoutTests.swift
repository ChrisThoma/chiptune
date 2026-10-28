import SwiftUI
import XCTest
@testable import Chiptune

final class ArrangementRowLayoutTests: XCTestCase {

    func testDefaultAndLargeSizesKeepTheOneLineRow() {
        for size in DynamicTypeSize.allCases where !size.isAccessibilitySize {
            XCTAssertEqual(ArrangementRowLayout.choose(for: size), .oneLine, "\(size)")
        }
    }

    func testAccessibilitySizesMoveRepeatsToASecondLine() {
        for size in DynamicTypeSize.allCases where size.isAccessibilitySize {
            XCTAssertEqual(ArrangementRowLayout.choose(for: size), .twoLines, "\(size)")
        }
    }
}
