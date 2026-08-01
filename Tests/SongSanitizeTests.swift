import XCTest
@testable import Chiptune

/// A cell in a decoded song holds either a rest, an explicit note-off, or a
/// MIDI note. `normalize` is the choke point where anything else — an older
/// format, a hand-edited file, corruption — must be scrubbed back to a rest.
final class SongSanitizeTests: XCTestCase {

    func testNormalizeScrubsInvalidCellsAndKeepsValidOnes() {
        var song = Song(name: "Sanitize")
        let input: [Int8] = [-128, -100, -3, -2, -1, 0, 60, 127]
        for (step, value) in input.enumerated() {
            song.patterns[0].rows[0][step] = value
        }

        song.normalize()

        let row = song.patterns[0].rows[0]
        // Valid values survive untouched.
        XCTAssertEqual(row[3], -2, "note-off must survive normalize")
        XCTAssertEqual(row[4], -1, "rest must survive normalize")
        XCTAssertEqual(row[5], 0, "lowest MIDI note must survive normalize")
        XCTAssertEqual(row[6], 60, "ordinary note must survive normalize")
        XCTAssertEqual(row[7], 127, "highest MIDI note must survive normalize")
        // Everything else becomes a rest.
        XCTAssertEqual(row[0], -1, "out-of-range sentinel must become a rest")
        XCTAssertEqual(row[1], -1, "out-of-range sentinel must become a rest")
        XCTAssertEqual(row[2], -1, "unknown negative sentinel must become a rest")
    }

    func testInvalidCellsSurviveDecodeButNotNormalize() throws {
        // Round-trip through JSON the way a saved file would arrive, then
        // normalize — the full path a malformed document takes on open.
        var song = Song(name: "Decode")
        song.patterns[0].rows[0][0] = -100
        song.patterns[0].rows[0][1] = 64

        let data = try JSONEncoder().encode(song)
        var decoded = try JSONDecoder().decode(Song.self, from: data)
        decoded.normalize()

        XCTAssertEqual(decoded.patterns[0].rows[0][0], -1)
        XCTAssertEqual(decoded.patterns[0].rows[0][1], 64)
    }
}
