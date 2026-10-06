import XCTest
@testable import Chiptune

/// A song file that will not decode used to be skipped without a word. These
/// pin that the store reports it, the studio says so once, and nothing on disk
/// is touched.
@MainActor
final class UnreadableSongTests: XCTestCase {

    private func plantCorrupt(in temp: TempStore, name: String = "\(UUID().uuidString).json") throws -> URL {
        let url = temp.directory.appendingPathComponent(name)
        try Data("{broken".utf8).write(to: url)
        return url
    }

    func testStoreReportsUnreadableFilesAlongsideSongs() throws {
        let temp = makeTempStore()
        temp.save(Song(name: "Fine"))
        _ = try plantCorrupt(in: temp)

        let library = temp.store.loadLibrary()
        XCTAssertEqual(library.songs.map(\.name), ["Fine"])
        XCTAssertEqual(library.unreadable.count, 1)
        XCTAssertEqual(temp.store.loadAll().map(\.name), ["Fine"])
    }

    func testLaunchWithUnreadableFileTellsTheUserAndLeavesTheFileAlone() throws {
        let temp = makeTempStore()
        temp.save(Song(name: "Fine"), makeCurrent: true)
        let bad = try plantCorrupt(in: temp)

        let studio = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        XCTAssertEqual(studio.song.name, "Fine", "which song opens must not change")
        let notice = try XCTUnwrap(studio.unreadableSongsNotice)
        XCTAssertEqual(notice, UnreadableSongs.message(count: 1))
        XCTAssertEqual(try Data(contentsOf: bad), Data("{broken".utf8), "the file must be left untouched")
    }

    func testNoNoticeWhenEverythingIsReadable() {
        let temp = makeTempStore()
        temp.save(Song(name: "Fine"), makeCurrent: true)
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }
        XCTAssertNil(studio.unreadableSongsNotice)
        _ = studio.loadLibrary()
        XCTAssertNil(studio.unreadableSongsNotice)
    }

    func testLibraryOpenDoesNotRepeatAnAlreadyReportedFile() throws {
        let temp = makeTempStore()
        temp.save(Song(name: "Fine"), makeCurrent: true)
        _ = try plantCorrupt(in: temp)
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }
        XCTAssertNotNil(studio.unreadableSongsNotice)

        studio.unreadableSongsNotice = nil // the user dismissed it
        XCTAssertEqual(studio.loadLibrary().map(\.name), ["Fine"])
        XCTAssertNil(studio.unreadableSongsNotice, "the same file must not be reported twice in a run")

        _ = try plantCorrupt(in: temp)
        _ = studio.loadLibrary()
        XCTAssertEqual(studio.unreadableSongsNotice, UnreadableSongs.message(count: 1),
                      "a newly broken file is news")
    }

    func testAReportedFileIsNotReportedAgainOnTheNextLaunch() throws {
        let temp = makeTempStore()
        temp.save(Song(name: "Fine"), makeCurrent: true)
        _ = try plantCorrupt(in: temp)

        let first = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in first.invalidateTimers() }
        XCTAssertNotNil(first.unreadableSongsNotice)

        // A cold launch is a new Studio on the same store and defaults.
        let second = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in second.invalidateTimers() }
        XCTAssertNil(second.unreadableSongsNotice, "the user can't act on it, so once is enough")
        _ = second.loadLibrary()
        XCTAssertNil(second.unreadableSongsNotice)
    }

    func testAReplacedOrChangedFileIsReportedAgain() throws {
        let temp = makeTempStore()
        temp.save(Song(name: "Fine"), makeCurrent: true)
        let bad = try plantCorrupt(in: temp)

        let first = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in first.invalidateTimers() }
        XCTAssertNotNil(first.unreadableSongsNotice)

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)],
                                              ofItemAtPath: bad.path)
        let second = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in second.invalidateTimers() }
        XCTAssertEqual(second.unreadableSongsNotice, UnreadableSongs.message(count: 1))
    }

    func testNoticeWording() {
        XCTAssertEqual(UnreadableSongs.title, "Load failed")
        XCTAssertEqual(UnreadableSongs.message(count: 1),
                       "1 saved song couldn't be read, so it's left out of your library. It may be damaged.")
        XCTAssertEqual(UnreadableSongs.message(count: 3),
                       "3 saved songs couldn't be read, so they're left out of your library. They may be damaged.")
    }
}
