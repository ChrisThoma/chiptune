import XCTest
@testable import Chiptune

/// The `.chipsong` format: writing one, and — the part that matters — reading
/// one back in.
///
/// An imported file is arbitrary JSON from wherever the user got it. It is the
/// only route by which values the UI cannot produce reach the DSP, so the
/// hostile cases here are the reason `Instrument.normalize()` exists.
final class SongDocumentTests: XCTestCase {

    private var temp: TempStore!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
    }

    override func tearDown() {
        temp = nil
        super.tearDown()
    }

    private func assertSameSong(_ a: Song, _ b: Song, _ message: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        var a = a, b = b
        let epoch = Date(timeIntervalSince1970: 0)
        a.modified = epoch
        b.modified = epoch
        XCTAssertEqual(a, b, message, file: file, line: line)
    }

    private func makeSong() -> Song {
        var song = Song(name: "Shared")
        song.tempo = 174
        song.tracks[0].instrument.volume = 0.42
        song.tracks[2].muted = true
        song.patterns[0].rows[0][5] = 64
        song.patterns.append(Pattern(name: "B", length: 8, trackCount: song.tracks.count))
        song.arrangement.append(SongSection(patternID: song.patterns[1].id, repeats: 3))
        song.normalize()
        return song
    }

    // MARK: Round trip

    func testWritingThenReadingGivesTheSameSong() throws {
        let song = makeSong()
        let url = try SongDocument.write(song)

        XCTAssertEqual(url.pathExtension, SongDocument.fileExtension)
        assertSameSong(try SongDocument.read(contentsOf: url), song)
    }

    func testTheWrittenFileIsNamedAfterTheSong() throws {
        var song = makeSong()
        song.name = "My Song / v2"
        let url = try SongDocument.write(song)

        XCTAssertEqual(url.deletingPathExtension().lastPathComponent, "My Song v2",
                       "the filename should be the song's name, minus anything a path can't hold")
    }

    func testASongWithNoUsableNameStillGetsAFilename() throws {
        var song = makeSong()
        song.name = "///"
        let url = try SongDocument.write(song)
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent, "chiptune")
    }

    func testTwoSongsWithTheSameNameDoNotOverwriteEachOther() throws {
        var first = makeSong()
        first.name = "Twin"
        var second = makeSong()
        second.id = UUID()
        second.name = "Twin"
        second.tempo = 90

        let firstURL = try SongDocument.write(first)
        let secondURL = try SongDocument.write(second)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try SongDocument.read(contentsOf: firstURL).tempo, 174,
                       "the first file was overwritten by the second")
    }

    /// The share file is the same JSON the library stores, so a song exported
    /// from one device is readable by `SongStore` on another.
    func testTheSharedFileIsTheSameFormatTheLibraryUses() throws {
        let song = makeSong()
        let url = try SongDocument.write(song)
        let data = try Data(contentsOf: url)

        var decoded = try JSONDecoder().decode(Song.self, from: data)
        decoded.normalize()
        assertSameSong(decoded, song)
    }

    // MARK: Rejecting rubbish

    func testGarbageIsRejected() {
        for bytes in ["", "{", "not json", "[1,2,3]", "{\"unrelated\": true}"] {
            XCTAssertThrowsError(try SongDocument.decode(Data(bytes.utf8)),
                                 "decoded \(bytes) as a song")
        }
    }

    /// A number too big for a Double doesn't reach `normalize` at all — the
    /// JSON decoder rejects the document first, which is a fine outcome and
    /// worth pinning so it doesn't quietly become a crash later.
    func testANumberTooLargeForADoubleIsRejected() {
        let overflowing = """
        { "name": "Overflow", "tempo": 1e400, "tracks": [
            { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] } } ] }
        """
        XCTAssertThrowsError(try SongDocument.decode(Data(overflowing.utf8)))
    }

    func testAJpegIsRejectedRatherThanCrashing() {
        // Arbitrary binary, the way a mis-picked file would arrive.
        let bytes = Data((0..<512).map { _ in UInt8.random(in: 0...255) })
        XCTAssertThrowsError(try SongDocument.decode(bytes))
    }

    func testReadingAMissingFileFails() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).chipsong")
        XCTAssertThrowsError(try SongDocument.read(contentsOf: missing))
    }

    // MARK: Hostile values

    /// The reason import waited on `Instrument.normalize()`. Every value here
    /// is one the UI's bounded controls cannot produce, and each of them
    /// reaches the DSP directly.
    func testHostileValuesAreSanitisedOnImport() throws {
        let hostile = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Hostile",
          "tempo": 1e300,
          "tracks": [
            { "kind": 0,
              "instrument": { "duty": 9999, "volume": 500, "decay": -3,
                              "arpeggio": [1000000, -1000000, 7, 12, 5, 9] } },
            { "kind": 2,
              "instrument": { "duty": -5, "volume": -2, "decay": 1e12, "arpeggio": [] } }
          ],
          "patterns": [
            { "id": "\(UUID().uuidString)", "name": "A", "length": 99999,
              "rows": [[60, -100, 127, -3], [48]] }
          ],
          "arrangement": []
        }
        """

        let song = try SongDocument.decode(Data(hostile.utf8))

        XCTAssertTrue(song.tempo.isFinite)
        XCTAssertTrue((40...300).contains(song.tempo))
        for track in song.tracks {
            XCTAssertTrue((0...1).contains(track.instrument.volume))
            XCTAssertTrue((0.01...4.0).contains(track.instrument.decay))
            XCTAssertTrue(Instrument.dutyCycles.indices.contains(track.instrument.duty))
            XCTAssertLessThanOrEqual(track.instrument.arpeggio.count, Instrument.maxArpeggioSteps)
            for semitones in track.instrument.arpeggio {
                XCTAssertLessThanOrEqual(abs(semitones), Instrument.maxArpeggioSemitones)
            }
        }
        XCTAssertTrue((4...Chip.maxSteps).contains(song.patterns[0].length))
        XCTAssertFalse(song.arrangement.isEmpty, "an empty arrangement isn't representable")

        // And the thing all of that is for: it renders, and it renders audio.
        let samples = RenderHarness.render(song: song, seconds: 0.5, songMode: true)
        XCTAssertFalse(samples.contains { !$0.isFinite },
                       "a hostile import put NaN into the output")
        XCTAssertLessThanOrEqual(RenderHarness.peak(samples), 1.0)
    }

    /// Songs written before patterns existed can be shared too.
    func testALegacyFileImports() throws {
        let legacy = """
        { "name": "Legacy share", "tempo": 128, "length": 8, "tracks": [
            { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] },
              "notes": [60, -1, 64, -1, 67, -1, -1, -1] } ] }
        """

        let song = try SongDocument.decode(Data(legacy.utf8))

        XCTAssertEqual(song.name, "Legacy share")
        XCTAssertEqual(song.patterns.count, 1)
        XCTAssertEqual(Array(song.patterns[0].rows[0].prefix(8)), [60, -1, 64, -1, 67, -1, -1, -1])
    }

    // MARK: Collisions

    /// Two people who both started from the same shared file have songs with
    /// the same id. Importing one over the other would silently destroy work.
    func testAnIdCollisionGetsAFreshIdentity() {
        let existing = makeSong()
        let incoming = existing

        let resolved = SongDocument.resolvingCollision(incoming, against: [existing.id])

        XCTAssertNotEqual(resolved.id, existing.id)
        XCTAssertEqual(resolved.name, "Shared (imported)")
    }

    func testNoCollisionMeansTheSongIsUntouched() {
        let song = makeSong()
        let resolved = SongDocument.resolvingCollision(song, against: [UUID(), UUID()])
        assertSameSong(resolved, song)
    }
}

/// Import as the app does it: read the file, resolve collisions, save, open.
@MainActor
final class StudioImportTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    private func writeSong(_ song: Song) throws -> URL {
        try SongDocument.write(song)
    }

    func testImportingASongAddsItToTheLibraryAndOpensIt() throws {
        var incoming = Song(name: "From a friend")
        incoming.tempo = 96
        incoming.patterns[0].rows[0][3] = 65
        let url = try writeSong(incoming)

        XCTAssertTrue(studio.importSong(from: url))

        XCTAssertEqual(studio.song.name, "From a friend")
        XCTAssertEqual(studio.song.tempo, 96)
        XCTAssertEqual(studio.song.patterns[0].rows[0][3], 65)
        XCTAssertNotNil(temp.store.load(id: studio.song.id), "an imported song must be saved")
        XCTAssertNil(studio.importError)
        // And it plays.
        XCTAssertEqual(Int(studio.engine.core.trackCount), studio.song.tracks.count)
    }

    /// The one that would lose work: importing a song whose id matches one
    /// already in the library.
    func testImportingASongAlreadyInTheLibraryDoesNotOverwriteIt() throws {
        var original = Song(name: "Mine")
        original.tempo = 120
        original.patterns[0].rows[0][0] = 60
        temp.save(original)

        var incoming = original
        incoming.tempo = 200
        incoming.patterns[0].rows[0][0] = 72
        let url = try writeSong(incoming)

        XCTAssertTrue(studio.importSong(from: url))

        let mine = try XCTUnwrap(temp.store.load(id: original.id))
        XCTAssertEqual(mine.tempo, 120, "the song already in the library was overwritten")
        XCTAssertEqual(mine.patterns[0].rows[0][0], 60)

        XCTAssertNotEqual(studio.song.id, original.id)
        XCTAssertEqual(studio.song.name, "Mine (imported)")
        XCTAssertEqual(studio.song.tempo, 200)
    }

    func testImportingRubbishReportsAnErrorAndLeavesTheOpenSongAlone() throws {
        studio.open(Song(name: "Working on this"))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("junk-\(UUID().uuidString).chipsong")
        try Data("absolutely not a song".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(studio.importSong(from: url))

        XCTAssertNotNil(studio.importError)
        XCTAssertEqual(studio.song.name, "Working on this",
                       "a failed import must not disturb what's open")
    }

    func testImportingAMissingFileReportsAnError() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString).chipsong")

        XCTAssertFalse(studio.importSong(from: missing))
        XCTAssertNotNil(studio.importError)
    }

    /// A successful import after a failed one must clear the message.
    func testASuccessfulImportClearsAPreviousError() throws {
        studio.importError = "an earlier failure"
        let url = try writeSong(Song(name: "Fine"))

        XCTAssertTrue(studio.importSong(from: url))
        XCTAssertNil(studio.importError)
    }

    // MARK: Sharing

    func testSharingPublishesAReadableFile() throws {
        var song = Song(name: "To share")
        song.tempo = 150
        studio.open(song)

        studio.share(studio.song)

        let url = try XCTUnwrap(studio.shareURL)
        XCTAssertEqual(url.pathExtension, "chipsong")
        XCTAssertEqual(try SongDocument.read(contentsOf: url).tempo, 150)
    }

    /// Share out, import back: the whole loop, ending with a playable song.
    func testASharedSongCanBeImportedBack() throws {
        var song = Song(name: "Round trip")
        song.tempo = 108
        song.patterns[0].rows[1][7] = 71
        studio.open(song)
        studio.share(studio.song)
        let url = try XCTUnwrap(studio.shareURL)

        // Import it into a different library, the way another device would.
        let other = makeTempStore()
        let receiver = Studio(store: other.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in receiver.invalidateTimers() }

        XCTAssertTrue(receiver.importSong(from: url))
        XCTAssertEqual(receiver.song.name, "Round trip")
        XCTAssertEqual(receiver.song.tempo, 108)
        XCTAssertEqual(receiver.song.patterns[0].rows[1][7], 71)
    }
}
