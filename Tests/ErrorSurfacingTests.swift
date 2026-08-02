import XCTest
@testable import Chiptune

/// Failures the app used to swallow. Each of these was a `try?` or an ignored
/// return value, which meant the app carried on looking fine while the thing
/// the user asked for hadn't happened.
@MainActor
final class ErrorSurfacingTests: XCTestCase {

    private func waitForExport(_ studio: Studio, timeout: TimeInterval = 30) {
        let done = expectation(description: "export finishes")
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                if !studio.isExporting { done.fulfill() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wait(for: [done], timeout: timeout)
        timer.invalidate()
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

        let defaults = UserDefaults(suiteName: "chiptune.tests.blocked.\(UUID().uuidString)")!
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

        let defaults = UserDefaults(suiteName: "chiptune.tests.throw.\(UUID().uuidString)")!
        let store = SongStore(directory: blocked, defaults: defaults)

        XCTAssertThrowsError(try store.save(Song(name: "Nope")))
    }
}
