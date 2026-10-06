import SwiftUI
import XCTest
@testable import Chiptune

/// Pulling down Control Center or a notification peek only makes the scene
/// `.inactive`, and that used to stop the engine mid-song. Any phase but
/// `.active` still saves; only `.background` stops playback.
final class ScenePhasePolicyTests: XCTestCase {
    func testInactiveSavesButKeepsPlaying() {
        XCTAssertTrue(ScenePhasePolicy.savesNow(entering: .inactive))
        XCTAssertFalse(ScenePhasePolicy.stopsEngine(entering: .inactive))
    }

    func testBackgroundSavesAndStops() {
        XCTAssertTrue(ScenePhasePolicy.savesNow(entering: .background))
        XCTAssertTrue(ScenePhasePolicy.stopsEngine(entering: .background))
    }

    func testActiveDoesNeither() {
        XCTAssertFalse(ScenePhasePolicy.savesNow(entering: .active))
        XCTAssertFalse(ScenePhasePolicy.stopsEngine(entering: .active))
    }
}
