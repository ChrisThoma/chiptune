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

/// Voice Control and Full Keyboard Access can't swipe an adjustable element,
/// so the stepper also offers its two steps as named actions, worded as the
/// system `Stepper` words them.
final class PlainStepperActionTests: XCTestCase {

    func testActionsAreNamedAsTheSystemStepperNamesThem() {
        XCTAssertEqual(PlainStepper.incrementActionName, "Increment")
        XCTAssertEqual(PlainStepper.decrementActionName, "Decrement")
    }

    func testActionsStepByOneInTheirDirection() {
        XCTAssertEqual(PlainStepper.delta(forIncrement: true), 1)
        XCTAssertEqual(PlainStepper.delta(forIncrement: false), -1)
    }
}

/// The minus and plus grow with Dynamic Type, so the glyph, which does,
/// stays inside the capsule.
final class PlainStepperSizeTests: XCTestCase {

    func testTheButtonsAreTheSystemSizeAtTheDefaultTextSize() {
        XCTAssertEqual(PlainStepper.buttonSize(scale: 1), CGSize(width: 46, height: 32))
    }

    func testTheButtonsGrowWithTheText() {
        XCTAssertEqual(PlainStepper.buttonSize(scale: 2), CGSize(width: 92, height: 64))
    }

    /// Never smaller than the system size, whatever the text size.
    func testTheButtonsNeverShrinkBelowTheSystemSize() {
        XCTAssertEqual(PlainStepper.buttonSize(scale: 0.8), CGSize(width: 46, height: 32))
    }
}
