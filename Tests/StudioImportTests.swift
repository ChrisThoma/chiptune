import XCTest
@testable import Chiptune

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

    /// A document URL can arrive while the library sheet is covering the
    /// editor. The imported song still needs to route visibly to the editor.
    func testWarmImportDismissesAPresentedSongLibrary() throws {
        let previousSongID = studio.song.id
        let url = try writeSong(studio.song)

        XCTAssertTrue(studio.importSong(from: url))

        XCTAssertFalse(SongLibraryPresentation.afterOpeningSong(
            isPresented: true,
            previousSongID: previousSongID,
            currentSongID: studio.song.id
        ))
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

    /// Share failures used to land in `importError`, which alerts under
    /// "Import failed" — the wrong words for a share that couldn't write its
    /// temp file. The two are separate now, and must stay separate.
    func testShareFailuresDoNotSurfaceAsImportFailures() throws {
        // `SongDocument.write` puts each song in its own temp directory. A
        // regular file sitting at that path makes creating the directory fail,
        // which is the only way sharing can fail at all.
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(studio.song.id.uuidString)", isDirectory: false)
        try? FileManager.default.removeItem(at: blocked)
        try Data("not a directory".utf8).write(to: blocked)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocked) }

        studio.share(studio.song)

        XCTAssertNil(studio.shareURL, "nothing was written, so there's nothing to share")
        XCTAssertNotNil(studio.shareError, "a share that failed must not do so quietly")
        XCTAssertTrue(studio.shareError?.contains(studio.song.name) ?? false,
                      "the message should name the song: \(studio.shareError ?? "nil")")
        XCTAssertNil(studio.importError,
                     "and it must not raise the alert titled “Import failed”")
    }

    func testASuccessfulShareClearsAPreviousError() {
        studio.shareError = "an earlier failure"

        studio.share(studio.song)

        XCTAssertNotNil(studio.shareURL)
        XCTAssertNil(studio.shareError, "a share that works clears the last one that didn't")
    }

    // MARK: Dropped songs

    // The half of the import path a drag shares with the file importer: the
    // song arrives already decoded, and still has to join the library, open,
    // and leave anything already there alone.

    func testImportingADecodedSongSavesItAndOpensIt() throws {
        var incoming = Song(name: "Dropped in")
        incoming.tempo = 96
        incoming.patterns[0].rows[0][3] = 65

        XCTAssertTrue(studio.importSong(decoded: incoming))

        XCTAssertEqual(studio.song.id, incoming.id)
        XCTAssertEqual(studio.song.name, "Dropped in")
        XCTAssertEqual(studio.song.tempo, 96)
        XCTAssertEqual(studio.song.patterns[0].rows[0][3], 65)
        XCTAssertNotNil(temp.store.load(id: studio.song.id),
                        "an imported song must be saved")
        XCTAssertNil(studio.importError)
        // And it plays.
        XCTAssertEqual(Int(studio.engine.core.trackCount), studio.song.tracks.count)
    }

    func testImportingADecodedSongAlreadyInTheLibraryDoesNotOverwriteIt() throws {
        var original = Song(name: "Mine")
        original.tempo = 120
        original.patterns[0].rows[0][0] = 60
        temp.save(original)

        var incoming = original
        incoming.tempo = 200
        incoming.patterns[0].rows[0][0] = 72

        XCTAssertTrue(studio.importSong(decoded: incoming))

        let mine = try XCTUnwrap(temp.store.load(id: original.id))
        XCTAssertEqual(mine.tempo, 120, "the song already in the library was overwritten")
        XCTAssertEqual(mine.patterns[0].rows[0][0], 60)

        XCTAssertNotEqual(studio.song.id, original.id)
        XCTAssertEqual(studio.song.name, "Mine (imported)")
        XCTAssertEqual(studio.song.tempo, 200)
    }

    func testASuccessfulDecodedImportClearsAPreviousError() {
        studio.importError = "an earlier failure"

        XCTAssertTrue(studio.importSong(decoded: Song(name: "Fine")))

        XCTAssertNil(studio.importError)
    }

    /// A dropped song skips `SongDocument.read`, so the normalisation that
    /// keeps unrepresentable values off the disk and out of the DSP has to
    /// happen on this path too.
    func testADecodedImportIsNormalisedBeforeItIsSaved() {
        var incoming = Song(name: "Hostile")
        incoming.tempo = .nan

        XCTAssertTrue(studio.importSong(decoded: incoming))

        XCTAssertFalse(studio.song.tempo.isNaN, "an imported tempo must be usable")
        XCTAssertNotNil(temp.store.load(id: studio.song.id),
                        "a NaN tempo fails to encode, so an unnormalised import is never saved")
    }
}
