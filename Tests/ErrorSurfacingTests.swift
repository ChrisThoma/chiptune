import XCTest
@testable import Chiptune

/// Failures the app used to swallow. Each of these was a `try?` or an ignored
/// return value, which meant the app carried on looking fine while the thing
/// the user asked for hadn't happened.
@MainActor
final class ErrorSurfacingTests: XCTestCase {

    // MARK: Delete

    /// Deleting a song whose file refuses to go must say so — silently keeping
    /// the file means the song reappears in the library on the next load.
    func testAFailedDeleteIsReported() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        let doomed = Song(name: "Doomed")
        temp.save(doomed)

        // A read-only directory keeps its entries: `removeItem` fails rather
        // than the file being gone.
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: temp.directory.path)
        addTeardownBlock {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.directory.path)
        }

        studio.delete(doomed)

        XCTAssertNotNil(studio.storageError, "a delete that failed must be surfaced")
    }

    // MARK: Export

    func testAFailedExportIsReported() {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { _ in .failed })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitForExport(studio)

        XCTAssertNil(studio.exportURL)
        XCTAssertFalse(studio.isExporting, "a failed export must still clear the busy flag")
        XCTAssertNotNil(studio.exportError, "the export failed and said nothing")
        XCTAssertTrue(studio.exportError?.contains(studio.song.name) ?? false,
                      "the message should name the song: \(studio.exportError ?? "nil")")
    }

    func testASuccessfulExportReportsNoError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ok-\(UUID().uuidString).wav")
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { _ in .success(url) })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitForExport(studio)

        XCTAssertEqual(studio.exportURL, url)
        XCTAssertNil(studio.exportError)
    }

    /// A failure then a success must not leave the old message sitting there
    /// for the next alert to show.
    func testRetryingAfterAFailureClearsTheMessage() {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { _ in .failed })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitForExport(studio)
        XCTAssertNotNil(studio.exportError)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("retry-\(UUID().uuidString).wav")
        studio.renderer = { _ in .success(url) }
        studio.export()
        waitForExport(studio)

        XCTAssertNil(studio.exportError, "a stale failure must not survive a successful retry")
    }

    // MARK: Saving

    /// The failure that loses work. Staged by pointing the store at a path that
    /// can't be written — a file where the songs directory should be.
    func testAFailedSaveIsReported() throws {
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocked-\(UUID().uuidString)")
        // A regular file, so creating a directory at this path fails and so
        // does writing a song "inside" it.
        try Data("not a directory".utf8).write(to: blocked)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocked) }

        let suiteName = "chiptune.tests.blocked.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // Without this the suite persists into the simulator's preferences for
        // good — the leak `TempStore.clean()` exists to prevent.
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let studio = Studio(store: SongStore(directory: blocked, defaults: defaults),
                            autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.song.name = "Unsaveable"
        studio.saveNow()

        XCTAssertNotNil(studio.storageError, "a save that failed must not do so quietly")
        XCTAssertTrue(studio.storageError?.contains("Unsaveable") ?? false,
                      "the message should name the song: \(studio.storageError ?? "nil")")
    }

    func testASuccessfulSaveClearsAPreviousFailure() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.storageError = "something went wrong earlier"
        studio.saveNow()

        XCTAssertNil(studio.storageError)
    }

    /// `SongStore.save` throwing is what makes the above possible; before this
    /// it was a `try?` and the caller could not have known.
    func testStoreSaveThrowsRatherThanFailingSilently() {
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocked-\(UUID().uuidString)")
        try? Data("not a directory".utf8).write(to: blocked)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocked) }

        let suiteName = "chiptune.tests.throw.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let store = SongStore(directory: blocked, defaults: defaults)

        XCTAssertThrowsError(try store.save(Song(name: "Nope")))
    }
}
