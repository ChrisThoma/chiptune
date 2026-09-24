import XCTest
@testable import Chiptune

/// `ScreenshotMode` reads `UserDefaults.standard` directly — that's how a
/// launch argument like `-shotPlaying YES` actually lands, so these tests set
/// and clear real standard-defaults keys rather than an injected suite. Every
/// key touched here is removed again in `tearDown`, so a failure mid-test
/// can't leak a mode into whatever suite happens to run next.
final class ScreenshotModeTests: XCTestCase {

    override func tearDown() {
        for mode in ScreenshotMode.allCases {
            UserDefaults.standard.removeObject(forKey: mode.rawValue)
        }
        super.tearDown()
    }

    func testNoArgumentRequestsNoMode() {
        XCTAssertNil(ScreenshotMode.requested)
    }

    func testPlayingKeyMapsToPlayingCase() {
        UserDefaults.standard.set(true, forKey: "shotPlaying")
        XCTAssertEqual(ScreenshotMode.requested, .playing)
    }

    func testPatternKeyMapsToPatternCase() {
        UserDefaults.standard.set(true, forKey: "shotPatternB")
        XCTAssertEqual(ScreenshotMode.requested, .pattern)
    }

    func testFalseValueSelectsNoMode() {
        UserDefaults.standard.set(false, forKey: "shotPlaying")
        XCTAssertNil(ScreenshotMode.requested)
    }

    func testNOStringValueSelectsNoModeBecauseUserDefaultsBoolTreatsItAsFalse() {
        // shoot.sh only ever passes YES, but the doc comment on ScreenshotMode
        // calls out that a value is required — this pins down that the wrong
        // one (NO) is inert rather than silently truthy.
        UserDefaults.standard.set("NO", forKey: "shotPatternB")
        XCTAssertNil(ScreenshotMode.requested)
    }

    func testYESStringValueSelectsItsMode() {
        // The value shoot.sh actually passes on the command line is the
        // string "YES", not a boxed Bool — `-bool` decodes NSString "YES"/"NO"
        // the same way `defaults` does, which is what makes this work.
        UserDefaults.standard.set("YES", forKey: "shotPlaying")
        XCTAssertEqual(ScreenshotMode.requested, .playing)
    }

    func testEachExistingKeyStillMapsToItsCase() {
        for mode in ScreenshotMode.allCases {
            UserDefaults.standard.set(true, forKey: mode.rawValue)
            XCTAssertEqual(ScreenshotMode.requested, mode)
            UserDefaults.standard.removeObject(forKey: mode.rawValue)
        }
    }
}
