import XCTest
@testable import Chiptune

extension XCTestCase {
    /// Spins the main run loop until `studio` finishes exporting. Polling
    /// rather than awaiting: export publishes by flipping `isExporting` on the
    /// main actor, and a timer poll keeps the test on the run loop the export
    /// itself needs. Was a private copy in three suites, drifting in timeout
    /// and tick.
    @MainActor
    func waitForExport(_ studio: Studio, timeout: TimeInterval = 60) {
        let done = expectation(description: "export finishes")
        // The repeating timer can fulfill again before `wait` returns and
        // invalidation lands; that's the timer racing its own cleanup, not a
        // test failure.
        done.assertForOverFulfill = false
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                if !studio.isExporting { done.fulfill() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }
}
