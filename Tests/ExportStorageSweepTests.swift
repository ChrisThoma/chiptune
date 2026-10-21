import XCTest
@testable import Chiptune

/// Exports live in tmp/<song id>/Name.{wav,mid,mp4}, and `pruneStale` only
/// tidies the folder of the song just exported. Every other song kept its
/// last video (about 60 MB a minute) for good, and a deleted song left its
/// folder behind. The launch sweep and the delete clean those up, and touch
/// nothing in tmp the exporters didn't write.
final class ExportStorageSweepTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sweep-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func touch(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    private func exists(_ path: String) -> Bool {
        fm.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    func testEverySongsExportsGoAndTheirEmptyFoldersWithThem() throws {
        let a = UUID().uuidString, b = UUID().uuidString
        try touch("\(a)/Song.wav")
        try touch("\(a)/Song.mid")
        try touch("\(a)/Song.mp4")
        try touch("\(b)/Other.MP4")

        ExportFiles.sweep(root: root)

        XCTAssertFalse(exists(a), "a song folder left empty goes too")
        XCTAssertFalse(exists(b))
    }

    func testFilesTheExportersDontWriteStay() throws {
        let a = UUID().uuidString
        try touch("\(a)/Song.wav")
        try touch("\(a)/notes.txt")
        try touch("\(a)/inner/Deep.wav")

        ExportFiles.sweep(root: root)

        XCTAssertFalse(exists("\(a)/Song.wav"))
        XCTAssertTrue(exists("\(a)/notes.txt"))
        XCTAssertTrue(exists("\(a)/inner/Deep.wav"), "only the folder's own files are the exporters'")
    }

    /// The song-file share folders, and anything not named for a song, are
    /// someone else's.
    func testNothingElseInTmpIsTouched() throws {
        let id = UUID().uuidString
        try touch("share-\(id)/Song.chipsong")
        try touch("somebody-else/Clip.mp4")
        try touch("Loose.wav")

        ExportFiles.sweep(root: root)

        XCTAssertTrue(exists("share-\(id)/Song.chipsong"))
        XCTAssertTrue(exists("somebody-else/Clip.mp4"))
        XCTAssertTrue(exists("Loose.wav"))
    }

    /// A render killed mid-way leaves its scratch behind; nothing is
    /// rendering at launch, so it all goes.
    func testScratchLeftByAKilledRenderGoes() throws {
        try touch("wav-scratch/\(UUID().uuidString).raw")
        try touch("video-scratch/\(UUID().uuidString).mp4")
        try touch("\(UUID().uuidString).raw")

        ExportFiles.sweep(root: root)

        XCTAssertFalse(exists("wav-scratch"))
        XCTAssertFalse(exists("video-scratch"))
        let left = try fm.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(left, [])
    }

    func testDeletingASongRemovesOnlyItsExports() throws {
        let doomed = UUID(), kept = UUID()
        try touch("\(doomed.uuidString)/Song.wav")
        try touch("\(doomed.uuidString)/Song.mp4")
        try touch("\(kept.uuidString)/Kept.wav")

        ExportFiles.removeExports(forSongID: doomed, root: root)

        XCTAssertFalse(exists(doomed.uuidString))
        XCTAssertTrue(exists("\(kept.uuidString)/Kept.wav"))
    }

    func testRemovingExportsOfASongWithNoneIsHarmless() {
        ExportFiles.removeExports(forSongID: UUID(), root: root)
        XCTAssertTrue(fm.fileExists(atPath: root.path))
    }
}

/// Deleting a song from the library takes its export folder with it.
@MainActor
final class SongDeleteExportCleanupTests: XCTestCase {
    func testDeletingASongRemovesItsExportFolder() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }
        let doomed = TestSongs.empty(name: "Doomed")
        temp.save(doomed)
        let file = ExportFiles.url(for: doomed, format: .wav)
        try Data("x".utf8).write(to: file)

        studio.delete(doomed)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }
}

/// All of an iPad's windows share one Studio, so the song deleted in one
/// window can be the one whose export another window is offering to share.
/// Its file stays for the share sheet; the next launch's sweep takes it.
final class DeleteKeepsTheExportOnOfferTests: XCTestCase {
    private let song = UUID()
    private let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)

    private func export(of id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("Song.mp4")
    }

    func testASongWithNothingOnOfferLosesItsExports() {
        XCTAssertTrue(ExportFiles.removesExportsOnDelete(songID: song, exportURL: nil, exportingSongID: nil))
        XCTAssertTrue(ExportFiles.removesExportsOnDelete(songID: song, exportURL: export(of: UUID()),
                                                         exportingSongID: UUID()))
    }

    func testTheSongWhoseExportIsOnOfferKeepsIt() {
        XCTAssertFalse(ExportFiles.removesExportsOnDelete(songID: song, exportURL: export(of: song),
                                                          exportingSongID: nil))
    }

    func testTheSongBeingExportedKeepsItsFolder() {
        XCTAssertFalse(ExportFiles.removesExportsOnDelete(songID: song, exportURL: nil, exportingSongID: song))
    }
}
