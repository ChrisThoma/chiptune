import XCTest
import SwiftUI
@testable import Chiptune

/// When a Photos retry is spent. It used to wait for the next `.active`
/// however late, so a retry left pending (Settings never reached, say)
/// put the share sheet up long after, over whatever the user was doing.
/// Now only a trip through `.background` after Open Settings counts.
final class PhotosRetryWatchTests: XCTestCase {
    private let retry = PhotosRetry(url: URL(fileURLWithPath: "/tmp/x/Song.mp4"), songID: UUID())

    func testActiveWithoutBackgroundDoesNotReshare() {
        var watch = PhotosRetryWatch()
        watch.settingsOpened(for: retry)
        XCTAssertNil(watch.phaseChanged(to: .inactive))
        XCTAssertNil(watch.phaseChanged(to: .active))
        XCTAssertEqual(watch.pending, retry, "still waiting for the trip to Settings")
    }

    func testBackgroundThenActiveResharesOnce() {
        var watch = PhotosRetryWatch()
        watch.settingsOpened(for: retry)
        XCTAssertNil(watch.phaseChanged(to: .inactive))
        XCTAssertNil(watch.phaseChanged(to: .background))
        XCTAssertNil(watch.phaseChanged(to: .inactive))
        XCTAssertEqual(watch.phaseChanged(to: .active), retry)
        XCTAssertNil(watch.pending)
        XCTAssertNil(watch.phaseChanged(to: .background))
        XCTAssertNil(watch.phaseChanged(to: .active), "spent")
    }

    /// A background trip from before Open Settings doesn't count.
    func testABackgroundBeforeSettingsWasOpenedDoesNotCount() {
        var watch = PhotosRetryWatch()
        XCTAssertNil(watch.phaseChanged(to: .background))
        watch.settingsOpened(for: retry)
        XCTAssertNil(watch.phaseChanged(to: .active))
    }

    /// A new export, the export ending, or another song opening clears it.
    func testANewExportInBetweenDropsTheRetry() {
        var watch = PhotosRetryWatch()
        watch.settingsOpened(for: retry)
        XCTAssertNil(watch.phaseChanged(to: .background))
        watch.clear()
        XCTAssertNil(watch.pending)
        XCTAssertNil(watch.phaseChanged(to: .active))
    }

    func testNothingPendingNeverReshares() {
        var watch = PhotosRetryWatch()
        XCTAssertNil(watch.phaseChanged(to: .background))
        XCTAssertNil(watch.phaseChanged(to: .active))
    }
}
