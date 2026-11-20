import XCTest
@testable import Chiptune

/// Per-note pitch effects in the model: how they're stored, saved, loaded and
/// cleaned up. The file format is the contract with older app versions and
/// with Android, so most of this is about what does and doesn't get written.
final class NoteEffectModelTests: XCTestCase {

    private func json(_ song: Song) throws -> String {
        String(decoding: try JSONEncoder().encode(song), as: UTF8.self)
    }

    private func roundTrip(_ song: Song) throws -> Song {
        try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
    }

    // MARK: Decoding

    func testASongWithoutEffectsDecodesWithEveryCellPlain() throws {
        var song = Song(name: "Plain")
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[2][9] = 48
        let decoded = try roundTrip(song)

        let pattern = try XCTUnwrap(decoded.patterns.first)
        XCTAssertEqual(pattern.effects.count, pattern.rows.count,
                       "effects must have one row per track")
        guard pattern.effects.count == pattern.rows.count else { return }
        for track in pattern.rows.indices {
            XCTAssertEqual(pattern.effects[track].count, Chip.maxSteps)
            for step in 0..<Chip.maxSteps {
                XCTAssertEqual(pattern.effect(track: track, step: step), .none)
            }
        }
    }

    func testACellsEffectRoundTrips() throws {
        var song = Song(name: "Wobble")
        song.patterns[0].rows[1][5] = 67
        song.patterns[0].setEffect(.vibrato, track: 1, step: 5)
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].setEffect(.glide, track: 0, step: 0)

        let decoded = try roundTrip(song)
        let pattern = try XCTUnwrap(decoded.patterns.first)
        XCTAssertEqual(pattern.effect(track: 1, step: 5), .vibrato)
        XCTAssertEqual(pattern.effect(track: 0, step: 0), .glide)
        XCTAssertEqual(pattern.effect(track: 1, step: 6), .none)
        assertSameSong(decoded, song, "a song with effects must survive a save and reopen")
    }

    func testEveryEffectRoundTrips() throws {
        var song = Song(name: "All")
        for (step, effect) in NoteEffect.allCases.enumerated() {
            song.patterns[0].rows[0][step] = 60
            song.patterns[0].setEffect(effect, track: 0, step: step)
        }
        let pattern = try XCTUnwrap(try roundTrip(song).patterns.first)
        for (step, effect) in NoteEffect.allCases.enumerated() {
            XCTAssertEqual(pattern.effect(track: 0, step: step), effect)
        }
    }

    /// A file from a newer build might carry an effect this one doesn't know.
    /// The note should still play — plain — and the song still open.
    func testUnknownEffectValuesDecodeAsNone() throws {
        var song = Song(name: "Future")
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[0][1] = 62
        song.patterns[0].rows[0][2] = 64
        song.patterns[0].setEffect(.slideUp, track: 0, step: 0)
        song.patterns[0].setEffect(.slideUp, track: 0, step: 1)
        song.patterns[0].setEffect(.slideUp, track: 0, step: 2)

        let data = try JSONEncoder().encode(song)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var patterns = try XCTUnwrap(object["patterns"] as? [[String: Any]])
        var effects = try XCTUnwrap(patterns[0]["effects"] as? [[Int]], "effects key missing")
        try XCTSkipIf(effects.isEmpty || effects[0].count < 3)
        effects[0][0] = 9
        effects[0][1] = 200
        effects[0][2] = -5
        patterns[0]["effects"] = effects
        object["patterns"] = patterns
        let edited = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Song.self, from: edited)
        let pattern = try XCTUnwrap(decoded.patterns.first)
        XCTAssertEqual(pattern.effect(track: 0, step: 0), .none, "9 is no effect this build knows")
        XCTAssertEqual(pattern.effect(track: 0, step: 1), .none, "200 doesn't even fit in Int8")
        XCTAssertEqual(pattern.effect(track: 0, step: 2), .none)
        XCTAssertEqual(pattern.rows[0][0], 60, "the note itself must survive")
    }

    // MARK: Encoding

    /// Songs without effects must save exactly as they did before effects
    /// existed, so older app versions and the golden files see no change.
    func testASongWithNoEffectsEncodesWithoutTheKey() throws {
        var song = Song(name: "Plain")
        song.patterns[0].rows[0][0] = 60
        XCTAssertFalse(try json(song).contains("\"effects\""))
    }

    func testASongWithAnEffectEncodesTheKey() throws {
        var song = Song(name: "Fx")
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].setEffect(.bendIn, track: 0, step: 0)
        XCTAssertTrue(try json(song).contains("\"effects\""))
    }

    func testLibraryFixturesReencodeWithoutEffects() throws {
        let names = ["song-library-boss-door.chipsong", "song-library-coin-rush.chipsong",
                     "song-library-neon-ascent.chipsong", "song-library-overworld-sketch.chipsong",
                     "song-library-slow-cartridge.chipsong"]
        for name in names {
            let url = try FixtureFiles.url(name)
            let song = try SongDocument.read(contentsOf: url)
            XCTAssertFalse(try json(song).contains("\"effects\""),
                           "\(url.lastPathComponent) gained an effects key")
        }
    }

    /// Clearing the last effect takes the key back out.
    func testClearingTheLastEffectDropsTheKey() throws {
        var song = Song(name: "Fx")
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].setEffect(.vibrato, track: 0, step: 0)
        song.patterns[0].setEffect(.none, track: 0, step: 0)
        XCTAssertFalse(try json(song).contains("\"effects\""))
    }

    // MARK: Normalize

    func testNormalizePadsShortEffectsAndTrimsLongOnes() throws {
        var song = Song(name: "Shape")
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].effects = [[NoteEffect.slideDown.rawValue]]
        song.normalize()
        var pattern = try XCTUnwrap(song.patterns.first)
        XCTAssertEqual(pattern.effects.count, pattern.rows.count)
        XCTAssertTrue(pattern.effects.allSatisfy { $0.count == Chip.maxSteps })
        XCTAssertEqual(pattern.effect(track: 0, step: 0), .slideDown, "a padded row keeps what it had")

        song.patterns[0].effects = Array(repeating: Array(repeating: 0, count: Chip.maxSteps + 9),
                                         count: song.tracks.count + 3)
        song.normalize()
        pattern = try XCTUnwrap(song.patterns.first)
        XCTAssertEqual(pattern.effects.count, pattern.rows.count)
        XCTAssertTrue(pattern.effects.allSatisfy { $0.count == Chip.maxSteps })
    }

    /// An effect only means something on a note. On a rest or an OFF it would
    /// be invisible in the grid and still saved in the file.
    func testNormalizeClearsEffectsOnRestsAndOffsAndUnknownValues() throws {
        var song = Song(name: "Stray")
        song.patterns[0].rows[0][0] = Chip.emptyNote
        song.patterns[0].rows[0][1] = Chip.noteOff
        song.patterns[0].rows[0][2] = 60
        song.patterns[0].rows[0][3] = 62
        try XCTSkipUnless(song.patterns[0].effects.first?.count == Chip.maxSteps)
        song.patterns[0].effects[0][0] = NoteEffect.vibrato.rawValue
        song.patterns[0].effects[0][1] = NoteEffect.vibrato.rawValue
        song.patterns[0].effects[0][2] = NoteEffect.vibrato.rawValue
        song.patterns[0].effects[0][3] = 42
        song.normalize()
        let pattern = try XCTUnwrap(song.patterns.first)
        XCTAssertEqual(pattern.effect(track: 0, step: 0), .none)
        XCTAssertEqual(pattern.effect(track: 0, step: 1), .none)
        XCTAssertEqual(pattern.effect(track: 0, step: 2), .vibrato)
        XCTAssertEqual(pattern.effects[safe: 0]?[safe: 3], 0, "an unknown stored value normalizes to none")
    }

    func testEffectLookupOutsideTheGridIsNone() {
        let pattern = Pattern(name: "A", trackCount: 2)
        XCTAssertEqual(pattern.effect(track: 9, step: 0), .none)
        XCTAssertEqual(pattern.effect(track: 0, step: 999), .none)
        XCTAssertEqual(pattern.effect(track: -1, step: -1), .none)
    }

    // MARK: Labels

    func testEachEffectHasASymbolAndAName() {
        XCTAssertEqual(NoteEffect.none.symbol, "")
        XCTAssertEqual(NoteEffect.slideUp.symbol, "↗")
        XCTAssertEqual(NoteEffect.slideDown.symbol, "↘")
        XCTAssertEqual(NoteEffect.vibrato.symbol, "~")
        XCTAssertEqual(NoteEffect.glide.symbol, "⌒")
        XCTAssertEqual(NoteEffect.bendIn.symbol, "⤴")

        XCTAssertEqual(NoteEffect.none.name, "No effect")
        XCTAssertEqual(NoteEffect.slideUp.name, "Slide up")
        XCTAssertEqual(NoteEffect.slideDown.name, "Slide down")
        XCTAssertEqual(NoteEffect.vibrato.name, "Vibrato")
        XCTAssertEqual(NoteEffect.glide.name, "Glide")
        XCTAssertEqual(NoteEffect.bendIn.name, "Bend in")
    }

    func testRawValuesMatchTheFileFormat() {
        XCTAssertEqual(NoteEffect.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5])
    }

    func testCellLabelCarriesTheSymbolAfterTheNote() {
        XCTAssertEqual(NoteName.label(76, effect: .slideUp), "E5↗")
        XCTAssertEqual(NoteName.label(79, effect: .vibrato), "G5~")
        XCTAssertEqual(NoteName.label(69, effect: .glide), "A4⌒")
        XCTAssertEqual(NoteName.label(76, effect: .none), "E5")
        XCTAssertEqual(NoteName.label(Chip.emptyNote, effect: .vibrato), "",
                       "a rest has no label, effect or not")
        XCTAssertEqual(NoteName.label(Chip.noteOff, effect: .vibrato), "REST",
                       "an OFF never carries an effect mark")
    }
}
