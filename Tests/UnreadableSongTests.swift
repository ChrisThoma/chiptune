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
        XCTAssertTrue(notice.contains("1 song"), notice)
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
        XCTAssertTrue(studio.unreadableSongsNotice?.contains("1 song") ?? false,
                      "a newly broken file is news")
    }

    func testNoticeWording() {
        XCTAssertTrue(UnreadableSongs.message(count: 1).contains("1 song couldn’t be read"))
        XCTAssertTrue(UnreadableSongs.message(count: 3).contains("3 songs couldn’t be read"))
        XCTAssertTrue(UnreadableSongs.message(count: 2).contains("left untouched"))
    }
}
