import XCTest
@testable import Chiptune

/// The persistence layer, which is the app's entire save story: there is no
/// Save button, so anything this loses is lost for good.
final class SongStoreTests: XCTestCase {

    private var temp: TempStore!
    private var store: SongStore { temp.store }

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
    }

    override func tearDown() {
        temp = nil
        super.tearDown()
    }

    /// `modified` is excluded: `save` stamps it on the way out, by design.
    private func assertSameSong(_ a: Song, _ b: Song, file: StaticString = #filePath,
                                line: UInt = #line) {
        var a = a, b = b
        let epoch = Date(timeIntervalSince1970: 0)
        a.modified = epoch
        b.modified = epoch
        XCTAssertEqual(a, b, file: file, line: line)
    }

    // MARK: Round trip

    func testSaveAndLoadRoundTripsTheWholeSong() throws {
        var song = Song(name: "Round trip")
        song.tempo = 174
        song.tracks[1].instrument.volume = 0.42
        song.tracks[2].muted = true
        song.patterns[0].rows[0][5] = 64
        song.patterns[0].length = 32
        song.patterns.append(Pattern(name: "B", length: 8, trackCount: song.tracks.count))
        song.arrangement.append(SongSection(patternID: song.patterns[1].id, repeats: 3))
        song.normalize()

        temp.save(song)

        assertSameSong(try XCTUnwrap(store.load(id: song.id)), song)
    }

    func testSaveStampsTheModifiedDate() throws {
        var song = Song(name: "Stamped")
        song.modified = Date(timeIntervalSince1970: 0)
        let before = Date()

        temp.save(song)

        let loaded = try XCTUnwrap(store.load(id: song.id))
        XCTAssertGreaterThanOrEqual(loaded.modified.timeIntervalSince1970,
                                    before.timeIntervalSince1970 - 1,
                                    "save should record when the song was written")
    }

    func testLoadingAnUnknownIdReturnsNil() {
        XCTAssertNil(store.load(id: UUID()))
    }

    // MARK: The current song

    func testLoadLastReturnsTheSongMarkedCurrent() throws {
        let first = Song(name: "First")
        let second = Song(name: "Second")
        temp.save(first, makeCurrent: true)
        temp.save(second)

        XCTAssertEqual(try XCTUnwrap(store.loadLast()).id, first.id)
    }

    /// The current song's file can be gone — deleted from the Files app, or
    /// lost to a restore — and the app still has to open something.
    func testLoadLastFallsBackToTheNewestSongWhenTheCurrentOneIsMissing() throws {
        let missing = Song(name: "Missing")
        temp.save(missing, makeCurrent: true)
        store.delete(missing)

        var older = Song(name: "Older")
        older.modified = Date(timeIntervalSince1970: 1000)
        var newer = Song(name: "Newer")
        newer.modified = Date(timeIntervalSince1970: 2000)
        temp.save(older)
        temp.save(newer)

        // `save` restamps, so "newest" is the one saved last.
        XCTAssertEqual(try XCTUnwrap(store.loadLast()).id, newer.id)
    }

    func testLoadLastReturnsNilOnAnEmptyLibrary() {
        XCTAssertNil(store.loadLast())
    }

    func testDeletingTheCurrentSongClearsTheCurrentKey() {
        let song = Song(name: "Doomed")
        temp.save(song, makeCurrent: true)

        store.delete(song)

        XCTAssertNil(store.load(id: song.id))
        XCTAssertNil(temp.defaults.string(forKey: "currentSongID"),
                     "the pointer must not outlive the file it points at")
    }

    func testDeletingAnotherSongLeavesTheCurrentKeyAlone() {
        let current = Song(name: "Current")
        let other = Song(name: "Other")
        temp.save(current, makeCurrent: true)
        temp.save(other)

        store.delete(other)

        XCTAssertEqual(temp.defaults.string(forKey: "currentSongID"), current.id.uuidString)
    }

    // MARK: Loading the library

    func testLoadAllReturnsNewestFirst() {
        let names = ["One", "Two", "Three"]
        for name in names { temp.save(Song(name: name)) }

        XCTAssertEqual(store.loadAll().map(\.name), names.reversed())
    }

    /// One bad file must not take the library down with it — that would be an
    /// app that opens to an empty song list and looks like it lost everything.
    func testCorruptFilesAreSkippedRatherThanFailingTheWholeLoad() throws {
        let good = Song(name: "Readable")
        temp.save(good)

        try Data("{ not json at all".utf8)
            .write(to: temp.directory.appendingPathComponent("\(UUID().uuidString).json"))
        try Data("{}".utf8)
            .write(to: temp.directory.appendingPathComponent("\(UUID().uuidString).json"))

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Readable")
    }

    func testNonJsonFilesAreIgnored() throws {
        temp.save(Song(name: "Readable"))
        try Data("nope".utf8).write(to: temp.directory.appendingPathComponent("stray.wav"))

        XCTAssertEqual(store.loadAll().count, 1)
    }

    func testLoadAllOnAnEmptyDirectoryIsEmptyRatherThanAFailure() {
        XCTAssertEqual(store.loadAll().count, 0)
    }

    // MARK: Migration

    /// Songs written before patterns existed keep their notes on the tracks
    /// themselves. Those files are still out there on people's phones.
    func testLegacyFormatMigratesItsNotesIntoPatternA() throws {
        let id = UUID()
        let legacy = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy",
          "tempo": 128,
          "length": 8,
          "tracks": [
            { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] },
              "notes": [60, -1, 64, -1, 67, -1, -1, -1] },
            { "kind": 2, "instrument": { "duty": 2, "volume": 0.9, "decay": 4.0, "arpeggio": [] },
              "notes": [48, -1, -1, -1, 48, -1, -1, -1] }
          ]
        }
        """
        try Data(legacy.utf8).write(to: temp.directory.appendingPathComponent("\(id.uuidString).json"))

        let song = try XCTUnwrap(store.load(id: id))

        XCTAssertEqual(song.name, "Legacy")
        XCTAssertEqual(song.tempo, 128)
        XCTAssertEqual(song.tracks.count, 2)
        XCTAssertEqual(song.patterns.count, 1, "the legacy notes become a single pattern")
        XCTAssertEqual(song.patterns[0].length, 8, "the song-level length becomes the pattern's")
        XCTAssertEqual(Array(song.patterns[0].rows[0].prefix(8)), [60, -1, 64, -1, 67, -1, -1, -1])
        XCTAssertEqual(Array(song.patterns[0].rows[1].prefix(8)), [48, -1, -1, -1, 48, -1, -1, -1])
        XCTAssertEqual(song.arrangement.count, 1)
        XCTAssertEqual(song.arrangement[0].patternID, song.patterns[0].id)

        // And once migrated it saves in the current format.
        temp.save(song)
        assertSameSong(try XCTUnwrap(store.load(id: id)), song)
    }

    func testLegacyFileWithoutAnIdStillLoads() throws {
        let legacy = """
        { "name": "No id", "tracks": [
            { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] },
              "notes": [60] } ] }
        """
        let url = temp.directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data(legacy.utf8).write(to: url)

        let songs = store.loadAll()
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].name, "No id")
        XCTAssertEqual(songs[0].patterns[0].rows[0][0], 60)
    }

    // MARK: Isolation

    /// Two stores on different directories must not see each other's songs —
    /// the property the whole test suite's isolation rests on.
    func testStoresOnDifferentDirectoriesAreIndependent() {
        let other = makeTempStore()
        temp.save(Song(name: "Mine"))

        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(other.store.loadAll().count, 0)
    }
}

/// Autosave: the debounce that means there is no Save button.
@MainActor
final class StudioAutosaveTests: XCTestCase {

    func testEditsAreWrittenAfterTheDebounceElapses() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store)
        studio.autosaveInterval = 0.05
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        let id = studio.song.id
        studio.song.name = "Edited"

        let written = expectation(description: "autosave writes")
        let poll = Timer(timeInterval: 0.02, repeats: true) { timer in
            if temp.store.load(id: id)?.name == "Edited" {
                timer.invalidate()
                written.fulfill()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        wait(for: [written], timeout: 5)
        poll.invalidate()
    }

    /// `saveNow` runs at moments where the app is about to lose its chance —
    /// backgrounding, opening another song — so it has to write immediately
    /// *and* cancel the pending timer, or a stale snapshot lands afterwards.
    func testSaveNowWritesImmediatelyAndCancelsThePendingTimer() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store)
        studio.autosaveInterval = 0.05
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.song.name = "First edit"
        studio.saveNow()
        XCTAssertEqual(try XCTUnwrap(temp.store.load(id: studio.song.id)).name, "First edit",
                       "saveNow must not wait for the debounce")

        // Rename behind the store's back. If saveNow left its timer armed, it
        // fires here and writes "First edit" over the top.
        let id = studio.song.id
        var behind = try XCTUnwrap(temp.store.load(id: id))
        behind.name = "Written elsewhere"
        temp.save(behind)

        let elapsed = expectation(description: "the cancelled timer's window passes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 5)

        XCTAssertEqual(try XCTUnwrap(temp.store.load(id: id)).name, "Written elsewhere",
                       "a timer left armed by saveNow overwrote a later write")
    }

    func testAutosaveDisabledMeansNoTimerFires() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.autosaveInterval = 0.05
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        let id = studio.song.id
        studio.saveNow()
        studio.song.name = "Not saved"

        let elapsed = expectation(description: "well past the debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 5)

        XCTAssertNotEqual(try XCTUnwrap(temp.store.load(id: id)).name, "Not saved",
                          "autosave was meant to be off")
    }
}

/// Export builds its own core rather than borrowing the live one. That is not
/// obvious from the call site and matters increasingly as export grows — this
/// pins it before cancel plumbing arrives.
@MainActor
final class ExportIsolationTests: XCTestCase {

    func testExportingMidPlaybackDoesNotDisturbTheLiveCore() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        var song = TestSongs.golden()
        song.tempo = 132
        studio.open(song)
        studio.setSongMode(true)

        let core = studio.engine.core
        core.start()
        // Advance the live sequencer to a known, non-zero position.
        _ = RenderHarness.renderMono(core, frames: 20_000)
        let stepBefore = core.currentStep
        let patternBefore = core.currentPattern
        XCTAssertGreaterThan(stepBefore, 0, "the live core should be mid-pattern for this to mean anything")

        // A full offline render of the same song, start to finish.
        XCTAssertNotNil(WavExport.render(song: studio.song))

        XCTAssertEqual(core.currentStep, stepBefore,
                       "the export moved the live sequencer's playhead")
        XCTAssertEqual(core.currentPattern, patternBefore)
        XCTAssertTrue(core.playing, "the export stopped live playback")
    }
}
