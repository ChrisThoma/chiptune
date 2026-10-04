import XCTest
@testable import Chiptune

/// Imported pattern names meet the rules the pattern bar enforces: at most six
/// characters, never blank, unique within the song.
final class PatternNameNormalizeTests: XCTestCase {

    private func song(named names: [String]) -> Song {
        var s = TestSongs.empty()
        s.patterns = names.map { Pattern(name: $0, length: 16, trackCount: s.tracks.count) }
        s.arrangement = s.patterns.map { SongSection(patternID: $0.id) }
        return s
    }

    func testLongNameIsClippedToSix() {
        var s = song(named: ["ABCDEFGHIJKLMNOPQRSTUVWXYZ"])
        s.normalize()
        XCTAssertEqual(s.patterns[0].name, "ABCDEF")
    }

    func testBlankNameGetsUniqueDefault() {
        var s = song(named: ["A", "   ", ""])
        s.normalize()
        XCTAssertEqual(s.patterns.map(\.name), ["A", "B", "C"])
    }

    func testDuplicateKeepsFirstAndRenamesLater() {
        var s = song(named: ["A", "A", "B", "B"])
        s.normalize()
        XCTAssertEqual(s.patterns.map(\.name), ["A", "C", "B", "D"])
    }

    func testReportedFixtureShape() {
        var s = song(named: ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "   ", "A", "A"])
        s.normalize()
        let names = s.patterns.map(\.name)
        XCTAssertEqual(Set(names).count, 4)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty && $0.count <= 6 })
        XCTAssertEqual(names[0], "ABCDEF")
        XCTAssertEqual(names[2], "A")
    }

    func testClippedCollisionIsMadeUnique() {
        var s = song(named: ["ABCDEFG", "ABCDEFH"])
        s.normalize()
        XCTAssertEqual(s.patterns[0].name, "ABCDEF")
        XCTAssertNotEqual(s.patterns[1].name, "ABCDEF")
    }

    func testValidUniqueNamesUnchangedAndIdempotent() {
        var s = song(named: ["Intro", "Verse", "x y"])
        s.normalize()
        XCTAssertEqual(s.patterns.map(\.name), ["Intro", "Verse", "x y"])
        let once = s
        s.normalize()
        XCTAssertEqual(s, once)
    }

    func testSurroundingWhitespaceTrimmed() {
        var s = song(named: ["  Hi  "])
        s.normalize()
        XCTAssertEqual(s.patterns[0].name, "Hi")
    }
}
