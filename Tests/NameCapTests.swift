import XCTest
@testable import Chiptune

final class NameCapTests: XCTestCase {
    func testClipsToTheCapLive() {
        XCTAssertEqual(NameCap.clip("abcdefghijklmnopqrst", to: Track.maxNameLength), "abcdefghijklmnop")
        XCTAssertEqual(NameCap.clip("abcdefgh", to: PatternNameCheck.maxLength), "abcdef")
    }

    func testShortTextAndExactCapPassThrough() {
        XCTAssertEqual(NameCap.clip("abc", to: 16), "abc")
        XCTAssertEqual(NameCap.clip("abcdefghijklmnop", to: 16), "abcdefghijklmnop")
    }

    func testCountsGraphemeClustersLikeTheSavedName() {
        let flags = String(repeating: "🇯🇵", count: 20)
        XCTAssertEqual(NameCap.clip(flags, to: 16).count, 16)
        XCTAssertEqual(NameCap.clip(flags, to: 16), String(flags.prefix(16)))
    }

    func testClippedTextMatchesTheSavedRule() {
        let typed = "abcdefghijklmnopqrst"
        var track = Track(kind: .pulse1)
        track.name = String(typed.prefix(Track.maxNameLength))
        XCTAssertEqual(NameCap.clip(typed, to: Track.maxNameLength), track.name)
    }

    func testDraftFollowsStoredNameOnlyWhenTheyDiffer() {
        XCTAssertNil(NameCap.draftUpdate(draft: "abc", stored: "abc"))
        XCTAssertNil(NameCap.draftUpdate(draft: "   ", stored: nil))
        XCTAssertEqual(NameCap.draftUpdate(draft: "abc", stored: nil), "")
        XCTAssertEqual(NameCap.draftUpdate(draft: "abc", stored: "xyz"), "xyz")
    }
}
