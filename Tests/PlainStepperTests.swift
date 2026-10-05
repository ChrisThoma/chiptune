import XCTest
@testable import Chiptune

/// The step rule behind ARR's and Export's Repeats control, tested without a
/// live accessibility tree: a tree walk found the element on one simulator and
/// nothing on a clean one, so it tested the simulator's state, not the app.
/// That the locked control reads as dimmed is a simulator check.
final class PlainStepperTests: XCTestCase {

    func testStepsWithinTheRange() {
        XCTAssertEqual(PlainStepper.stepped(1, by: 1, in: 1...16, isEnabled: true), 2)
        XCTAssertEqual(PlainStepper.stepped(5, by: -1, in: 1...16, isEnabled: true), 4)
    }

    func testStopsAtEitherEnd() {
        XCTAssertEqual(PlainStepper.stepped(1, by: -1, in: 1...16, isEnabled: true), 1)
        XCTAssertEqual(PlainStepper.stepped(16, by: 1, in: 1...16, isEnabled: true), 16)
    }

    /// Export locks Repeats while a render runs; a VoiceOver swipe on the
    /// locked control must not change the count under it.
    func testALockedStepperDoesNotStep() {
        XCTAssertEqual(PlainStepper.stepped(3, by: 1, in: 1...16, isEnabled: false), 3)
        XCTAssertEqual(PlainStepper.stepped(3, by: -1, in: 1...16, isEnabled: false), 3)
    }
}
