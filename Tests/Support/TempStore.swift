import Foundation
import XCTest
@testable import Chiptune

/// A `SongStore` on a throwaway directory with its own defaults suite.
///
/// Anything that constructs a `Studio` needs one of these. The default store
/// writes into the real Documents folder and `UserDefaults.standard`, which
/// makes tests order-dependent the moment one of them saves a song: the next
/// test's `loadLast()` picks it up.
struct TempStore {
    let store: SongStore
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults

    init(function: String = #function) {
        let id = UUID().uuidString
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chiptune-tests-\(id)", isDirectory: true)
        suiteName = "chiptune.tests.\(id)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SongStore(directory: directory, defaults: defaults)
        // The store itself only creates the directory when it first writes,
        // which is the right behaviour for the app but leaves the migration
        // tests — which plant a file before the store has ever been used —
        // writing into a directory that isn't there yet.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Saves as test setup. `SongStore.save` throws so the app can report a
    /// failed write, but a write into a fresh temp directory failing means the
    /// machine is broken, not the code — so that fails the test outright rather
    /// than making every arrange step `try`.
    func save(_ song: Song, makeCurrent: Bool = false,
              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try store.save(song, makeCurrent: makeCurrent), file: file, line: line)
    }

    /// Call from `tearDown`. Leaving the suite behind persists it to disk in
    /// the simulator's preferences for good.
    func clean() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

extension XCTestCase {
    /// A store scoped to one test, cleaned up when the test ends.
    func makeTempStore() -> TempStore {
        let temp = TempStore()
        addTeardownBlock { temp.clean() }
        return temp
    }
}
