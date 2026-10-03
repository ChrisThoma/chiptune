import XCTest
@testable import Chiptune

@MainActor
final class PatternRenameFooterTests: XCTestCase {
    private let names = ["A", "B", "C"]

    func testDuplicateOfAnotherPatternIsExplained() {
        XCTAssertEqual(PatternNameCheck.evaluate("A", among: names, renaming: 1), .duplicate)
        XCTAssertEqual(PatternNameCheck.footer(for: "A", among: names, renaming: 1),
                       "Another pattern already uses this name.")
    }

    func testDuplicateIgnoresSurroundingSpacesButNotCase() {
        XCTAssertEqual(PatternNameCheck.evaluate(" A ", among: names, renaming: 1), .duplicate)
        XCTAssertEqual(PatternNameCheck.evaluate("a", among: names, renaming: 1), .accepted("a"))
    }

    func testBlankKeepsTheCounterAndIsRefused() {
        XCTAssertEqual(PatternNameCheck.evaluate("  ", among: names, renaming: 1), .blank)
        XCTAssertEqual(PatternNameCheck.footer(for: "", among: names, renaming: 1),
                       "Up to 6 characters — 0 of 6 used.")
    }

    func testUniqueAndOwnNameKeepTheCounter() {
        XCTAssertEqual(PatternNameCheck.evaluate("Zed", among: names, renaming: 1), .accepted("Zed"))
        XCTAssertEqual(PatternNameCheck.footer(for: "Zed", among: names, renaming: 1),
                       "Up to 6 characters — 3 of 6 used.")
        XCTAssertEqual(PatternNameCheck.evaluate("B", among: names, renaming: 1), .accepted("B"))
    }

    func testStudioDecisionMatchesTheSharedCheck() {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(TestSongs.twoPatterns())
        let list = studio.song.patterns.map(\.name)
        for name in ["", " ", list[0], list[1], "Zed", "toolongname"] {
            for i in list.indices {
                XCTAssertEqual(studio.acceptablePatternName(name, for: i),
                               PatternNameCheck.evaluate(name, among: list, renaming: i).acceptedName)
            }
        }
    }
}
