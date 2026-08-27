import XCTest
import SwiftUI
@testable import Chiptune

/// Which metrics a window of a given size and size class gets.
///
/// The rule this pins down is that neither input decides on its own: the size
/// class picks the numbers, and the proportions pick the arrangement. Getting
/// that wrong is invisible on the device you happened to test on and obvious
/// on every other one — an iPad in a narrow Split View slice drawn with
/// iPad-sized cells, or a portrait iPad with the keyboard in a side column
/// that leaves the grid a sliver.
final class LayoutTests: XCTestCase {

    /// iPad Pro 11-inch, the two ways round.
    private let padPortrait = CGSize(width: 834, height: 1210)
    private let padLandscape = CGSize(width: 1210, height: 834)
    /// iPhone 15 Pro.
    private let phonePortrait = CGSize(width: 393, height: 852)

    func testCompactWidthGetsPhoneMetricsWhateverTheSize() {
        XCTAssertEqual(ChipLayout.resolve(size: phonePortrait, horizontalSizeClass: .compact),
                       .phone)
        // A Split View slice is iPad-sized in one dimension and still compact.
        XCTAssertEqual(ChipLayout.resolve(size: CGSize(width: 320, height: 1210),
                                          horizontalSizeClass: .compact),
                       .phone)
    }

    /// SwiftUI hands back a nil size class before the first layout pass.
    func testUnknownSizeClassFallsBackToPhone() {
        XCTAssertEqual(ChipLayout.resolve(size: padLandscape, horizontalSizeClass: nil), .phone)
    }

    func testRegularWidthGrowsTheGridAndKeys() {
        let layout = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertGreaterThan(layout.gridRowHeight, ChipLayout.phone.gridRowHeight)
        XCTAssertGreaterThan(layout.gridMinColumnWidth, ChipLayout.phone.gridMinColumnWidth)
        XCTAssertGreaterThan(layout.keyboardHeight, ChipLayout.phone.keyboardHeight)
    }

    func testPortraitStacksAndCapsTheKeyboardWidth() {
        let layout = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertFalse(layout.usesSideKeyboard)
        XCTAssertLessThan(layout.keyboardMaxWidth, padPortrait.width,
                          "Keys spread across the full width stop reading as a keyboard")
    }

    func testLandscapeMovesTheKeysBesideTheGrid() {
        let layout = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(layout.usesSideKeyboard)
        // The column is the cap in this arrangement, so the keys fill it.
        XCTAssertEqual(layout.keyboardMaxWidth, .infinity)
        XCTAssertGreaterThan(layout.keyboardHeight,
                             ChipLayout.resolve(size: padPortrait,
                                                horizontalSizeClass: .regular).keyboardHeight)
    }

    /// A square-ish window is the boundary between the two arrangements, and
    /// the tie has to break somewhere: equal sides stack rather than split,
    /// so the grid keeps the full width.
    func testSquareWindowStacks() {
        let layout = ChipLayout.resolve(size: CGSize(width: 900, height: 900),
                                        horizontalSizeClass: .regular)
        XCTAssertFalse(layout.usesSideKeyboard)
    }

    /// The grid has to fit beside the keyboard column with room to spare, or
    /// the side arrangement is worse than the stacked one it replaces.
    func testSideKeyboardLeavesTheGridMostOfTheWindow() {
        let gridWidth = padLandscape.width - ChipLayout.sideKeyboardWidth
        XCTAssertGreaterThan(gridWidth, padLandscape.width * 0.6)
    }

    /// The hole the proportions rule left open. Rotation never produces a
    /// window this shape, but Stage Manager and Slide Over both can: wider
    /// than tall, still regular, and not wide enough to give the grid anything
    /// worth having once the keyboard column has taken its 400pt.
    func testShortWideWindowStacksRatherThanSqueezingTheGrid() {
        let squat = CGSize(width: ChipLayout.minimumSideBySideWidth - 1, height: 700)
        XCTAssertGreaterThan(squat.width, squat.height,
                             "This case only matters while the proportions say split")
        XCTAssertFalse(ChipLayout.resolve(size: squat, horizontalSizeClass: .regular)
                        .usesSideKeyboard)

        let wideEnough = CGSize(width: ChipLayout.minimumSideBySideWidth, height: 700)
        XCTAssertTrue(ChipLayout.resolve(size: wideEnough, horizontalSizeClass: .regular)
                        .usesSideKeyboard)
    }

    /// The threshold has to sit under every window an iPad can actually be
    /// held in landscape at, or rotating one would stack it.
    func testEveryLandscapeIPadIsWideEnoughToSplit() {
        // 11-inch, 13-inch, and the 10th-generation iPad, landscape.
        for width in [1194.0, 1366.0, 1180.0] {
            XCTAssertGreaterThan(width, ChipLayout.minimumSideBySideWidth,
                                 "\(width)pt landscape should still split")
        }
    }

    func testChromeStopsSpreadingOnIPadAndNeverDoesOnIPhone() {
        let pad = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertLessThan(pad.chromeMaxWidth,
                          padLandscape.width - ChipLayout.sideKeyboardWidth,
                          "Capped wider than the grid column is no cap at all")
        XCTAssertEqual(ChipLayout.phone.chromeMaxWidth, .infinity)
    }

    /// Where the sound controls go, which is one choice with three answers and
    /// no overlap between them: docked in the side column, anchored to the
    /// track header as a popover, or presented as a sheet.
    func testTheInstrumentEditorGoesExactlyOnePlacePerLayout() {
        let landscape = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(landscape.docksInstrumentEditor)
        XCTAssertFalse(landscape.presentsInstrumentAsPopover)

        let portrait = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertFalse(portrait.docksInstrumentEditor)
        XCTAssertTrue(portrait.presentsInstrumentAsPopover)

        // The phone keeps the sheet it has always had.
        let phone = ChipLayout.resolve(size: phonePortrait, horizontalSizeClass: .compact)
        XCTAssertFalse(phone.docksInstrumentEditor)
        XCTAssertFalse(phone.presentsInstrumentAsPopover)
    }

    func testAccessibilityStackMakesTheLandscapeInstrumentEditorReachable() {
        let landscape = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(landscape.docksInstrumentEditor, "precondition")

        let stacked = landscape.withoutDockedInstrumentEditor

        XCTAssertFalse(stacked.docksInstrumentEditor)
        XCTAssertTrue(stacked.presentsInstrumentAsPopover)
    }

    func testReviewRequestOnlyFiresForACompletedShare() {
        XCTAssertTrue(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .completed))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .cancelled))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .failed))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: false, outcome: .completed))
    }

    /// A cancelled or failed share must not spend the milestone: the user
    /// keeps their eligibility for the next share that actually completes.
    func testCancellingOrFailingAShareLeavesTheMilestoneUnadvanced() {
        let cancelled = ReviewPromptPolicy.afterShareDismiss(
            eligible: true, outcome: .cancelled, successfulExports: 5, lastRequestExportCount: 0)
        XCTAssertFalse(cancelled.shouldRequestReview)
        XCTAssertEqual(cancelled.lastRequestExportCount, 0, "a cancelled share must not spend the milestone")

        let failed = ReviewPromptPolicy.afterShareDismiss(
            eligible: true, outcome: .failed, successfulExports: 5, lastRequestExportCount: 0)
        XCTAssertFalse(failed.shouldRequestReview)
        XCTAssertEqual(failed.lastRequestExportCount, 0, "a failed share must not spend the milestone")

        let completed = ReviewPromptPolicy.afterShareDismiss(
            eligible: true, outcome: .completed, successfulExports: 5, lastRequestExportCount: 0)
        XCTAssertTrue(completed.shouldRequestReview)
        XCTAssertEqual(completed.lastRequestExportCount, 5, "a completed share spends the milestone")

        let ineligible = ReviewPromptPolicy.afterShareDismiss(
            eligible: false, outcome: .completed, successfulExports: 5, lastRequestExportCount: 2)
        XCTAssertFalse(ineligible.shouldRequestReview)
        XCTAssertEqual(ineligible.lastRequestExportCount, 2, "not due at all, so nothing to advance")
    }

    func testReviewRequestRetriesAtALaterExportMilestone() {
        XCTAssertFalse(ReviewPromptPolicy.isDue(successfulExports: 2,
                                                lastRequestExportCount: 0))
        XCTAssertTrue(ReviewPromptPolicy.isDue(successfulExports: 3,
                                               lastRequestExportCount: 0))
        XCTAssertFalse(ReviewPromptPolicy.isDue(successfulExports: 12,
                                                lastRequestExportCount: 3))
        XCTAssertTrue(ReviewPromptPolicy.isDue(successfulExports: 13,
                                               lastRequestExportCount: 3))
    }

    func testCapacityWarningAnnouncesOnlyOnThresholdCrossing() {
        XCTAssertTrue(ArrangementCapacityAnnouncement.shouldAnnounce(
            previouslyExceeded: false, nowExceeds: true
        ))
        XCTAssertFalse(ArrangementCapacityAnnouncement.shouldAnnounce(
            previouslyExceeded: true, nowExceeds: true
        ))
        XCTAssertFalse(ArrangementCapacityAnnouncement.shouldAnnounce(
            previouslyExceeded: true, nowExceeds: false
        ))
    }

    // MARK: Export sheet accessibility

    /// The pure mapping VoiceOver's increment/decrement drives, extracted so
    /// it can be tested without a live accessibility tree. This does not
    /// prove the picker is wired up — see the simulator accessibility-tree
    /// check for that.
    func testTailModeAdjustedMapping() {
        XCTAssertEqual(ExportOptions.TailMode.seamlessLoop.adjusted(.increment), .ringOut)
        XCTAssertEqual(ExportOptions.TailMode.ringOut.adjusted(.decrement), .seamlessLoop)
        XCTAssertEqual(ExportOptions.TailMode.ringOut.adjusted(.increment), .ringOut,
                       "already at the far end, increment should not wrap")
        XCTAssertEqual(ExportOptions.TailMode.seamlessLoop.adjusted(.decrement), .seamlessLoop,
                       "already at the near end, decrement should not wrap")
    }

    /// The UIKit node itself: a real accessibility element with the adjustable
    /// trait, whose increment/decrement calls forward to the closure it was
    /// configured with.
    func testAdjustableViewIsAnAdjustableAccessibilityElementThatForwardsToItsClosure() {
        let view = AccessibilityAdjustableControl.AdjustableView()
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityTraits, .adjustable)

        var seen: [AccessibilityAdjustmentDirection] = []
        view.adjust = { seen.append($0) }

        view.accessibilityIncrement()
        view.accessibilityDecrement()

        XCTAssertEqual(seen, [.increment, .decrement])
    }
}
