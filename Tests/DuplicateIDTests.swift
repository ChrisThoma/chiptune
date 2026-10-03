import XCTest
@testable import Chiptune

/// Imported or stored songs can repeat an id. Everything in the editor looks
/// things up by id and takes the first match, so a repeat makes the later
/// pattern, track or section unreachable. Normalizing gives repeats fresh ids.
final class DuplicateIDTests: XCTestCase {

    private func roundTrip(_ song: Song) throws -> Song {
        try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
    }

    private func twoPatternSong() -> Song {
        var song = TestSongs.twoPatterns()
        song.patterns[0].rows[0][0] = 60
        song.patterns[1].rows[0][0] = 72
        song.patterns[1].id = song.patterns[0].id
        song.arrangement[1].patternID = song.patterns[0].id
        return song
    }

    func testDecodeGivesDuplicatePatternsUniqueIdsAndKeepsTheirNotes() throws {
        let original = twoPatternSong()
        let loaded = try roundTrip(original)

        XCTAssertEqual(Set(loaded.patterns.map(\.id)).count, 2)
        XCTAssertEqual(loaded.patterns[0].id, original.patterns[0].id, "first occurrence keeps its id")
        XCTAssertEqual(loaded.patterns[0].rows[0][0], 60)
        XCTAssertEqual(loaded.patterns[1].rows[0][0], 72)
        XCTAssertEqual(loaded.patterns[1].name, "B")
    }

    func testSectionsThatSharedTheIdStillPointAtTheFirstPattern() throws {
        let loaded = try roundTrip(twoPatternSong())

        XCTAssertEqual(loaded.arrangement.count, 2)
        for section in loaded.arrangement {
            XCTAssertNotNil(loaded.patternIndex(id: section.patternID))
            XCTAssertEqual(section.patternID, loaded.patterns[0].id)
        }
    }

    func testDecodeGivesDuplicateTrackIdsUniqueIds() throws {
        var song = Song(name: "Tracks")
        song.tracks[1].id = song.tracks[0].id
        let loaded = try roundTrip(song)

        XCTAssertEqual(Set(loaded.tracks.map(\.id)).count, loaded.tracks.count)
        XCTAssertEqual(loaded.tracks[0].id, song.tracks[0].id)
    }

    func testDecodeGivesDuplicateSectionIdsUniqueIds() throws {
        var song = Song(name: "Sections")
        song.arrangement.append(song.arrangement[0])
        let loaded = try roundTrip(song)

        XCTAssertEqual(loaded.arrangement.count, 2)
        XCTAssertEqual(Set(loaded.arrangement.map(\.id)).count, 2)
    }

    func testSongWithUniqueIdsIsLeftAlone() throws {
        let song = TestSongs.twoPatterns()
        let loaded = try roundTrip(song)

        XCTAssertEqual(loaded.patterns.map(\.id), song.patterns.map(\.id))
        XCTAssertEqual(loaded.tracks.map(\.id), song.tracks.map(\.id))
        XCTAssertEqual(loaded.arrangement.map(\.id), song.arrangement.map(\.id))
    }

    func testStoreLoadRepairsASavedDuplicateIdSong() throws {
        let temp = makeTempStore()
        defer { _ = temp }
        let song = twoPatternSong()
        // Written raw: save() would only store what the model already allows.
        let data = try JSONEncoder().encode(song)
        try data.write(to: temp.directory.appendingPathComponent("\(song.id.uuidString).json"))

        let loaded = try XCTUnwrap(temp.store.load(id: song.id))
        XCTAssertEqual(Set(loaded.patterns.map(\.id)).count, 2)
        XCTAssertEqual(loaded.patterns[1].rows[0][0], 72)
        XCTAssertEqual(try XCTUnwrap(temp.store.loadAll().first).patterns.count, 2)
    }

    func testNormalizeInPlaceRepairsDuplicates() {
        var song = twoPatternSong()
        song.normalize()
        XCTAssertEqual(Set(song.patterns.map(\.id)).count, 2)
    }
}
