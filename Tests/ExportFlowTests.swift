import XCTest
@testable import Chiptune

/// The hand-off from the export panel to the share sheet.
///
/// The two screens have different hosts now that export is a popover over the
/// ••• menu, and UIKit refuses to present the share sheet while the popover is
/// still dismissing: asking for both in one transaction got the popover down
/// and nothing else, leaving a rendered WAV with no way out of the app. So the
/// render only remembers that a share is owed, and the panel's disappearance
/// is what spends it. The order is invisible on screen when it works and
/// silent when it doesn't, which is why it's pinned here.
final class ExportFlowTests: XCTestCase {

    private let url = URL(fileURLWithPath: "/tmp/song.wav")

    /// A render that produced nothing — canceled, or failed — changes nothing.
    func testNoURLAsksForNothing() {
        XCTAssertEqual(ExportFlow.afterRender(url: nil, exportPresented: true),
                       ExportFlow.Step())
    }

    func testRenderFromThePanelQueuesTheShareRatherThanPresentingIt() {
        let step = ExportFlow.afterRender(url: url, exportPresented: true)
        XCTAssertTrue(step.closeExport)
        XCTAssertTrue(step.shareWhenExportCloses)
        XCTAssertFalse(step.shareNow, "the panel is still on screen")
    }

    /// Nothing is going to disappear, so nothing would ever spend the flag.
    func testRenderWithNoPanelUpSharesImmediately() {
        let step = ExportFlow.afterRender(url: url, exportPresented: false)
        XCTAssertFalse(step.closeExport)
        XCTAssertFalse(step.shareWhenExportCloses)
        XCTAssertTrue(step.shareNow)
    }

    func testPanelClosingSpendsTheQueuedShare() {
        XCTAssertTrue(ExportFlow.afterExportClosed(pendingShare: true).shareNow)
    }

    /// Closing the panel by hand, or with Escape, is not a share.
    func testPanelClosingWithNothingQueuedSharesNothing() {
        XCTAssertEqual(ExportFlow.afterExportClosed(pendingShare: false),
                       ExportFlow.Step())
    }

    /// The Close button pairs a cancel with its dismiss, but a swipe-to-dismiss
    /// or an outside tap on the popover reaches `onDisappear` with no cancel
    /// having happened. A render still in flight at that point must not be
    /// left to finish unobserved — its eventual error would have nowhere left
    /// to be shown.
    func testPanelDisappearingMidRenderAsksForACancel() {
        XCTAssertTrue(ExportFlow.afterPanelDisappeared(isExporting: true))
    }

    /// The panel disappearing because the render already finished — success or
    /// failure — must not re-cancel a render that isn't running.
    func testPanelDisappearingAfterTheRenderFinishedAsksForNothing() {
        XCTAssertFalse(ExportFlow.afterPanelDisappeared(isExporting: false))
    }

    /// Backing out of the share sheet without sharing is "let me try another
    /// ending", so the panel comes back for it.
    func testCanceledShareReturnsToTheExportPanel() {
        XCTAssertTrue(ExportFlow.reopensExportAfterShare(outcome: .canceled))
    }

    /// The file went somewhere; the job is done.
    func testCompletedShareLeavesTheExportPanelClosed() {
        XCTAssertFalse(ExportFlow.reopensExportAfterShare(outcome: .completed))
    }

    /// A failed share is already raising its own alert, which a popover
    /// coming up underneath would fight for the screen.
    func testFailedShareLeavesTheExportPanelClosed() {
        XCTAssertFalse(ExportFlow.reopensExportAfterShare(outcome: .failed))
    }

    // MARK: Reading a finished export off the attempt counter

    /// Exporting the same song in the same format again writes the same path,
    /// and a MIDI file can land before SwiftUI's next pass, so the URL's
    /// clear-then-set can collapse into no change at all. The attempt counter
    /// always moves, so it is what says a render finished.
    func testTheSameFileTwiceInARowIsSharedTwice() {
        XCTAssertEqual(ExportFlow.finishedExport(previousAttempt: 0, completedAttempt: 1, url: url), url)
        XCTAssertEqual(ExportFlow.finishedExport(previousAttempt: 1, completedAttempt: 2, url: url), url)
    }

    /// A canceled or failed render finishes with no file: nothing to share.
    func testAnAttemptThatLeftNoFileSharesNothing() {
        XCTAssertNil(ExportFlow.finishedExport(previousAttempt: 1, completedAttempt: 2, url: nil))
    }

    /// The counter not moving forward is not a render finishing, whatever
    /// file is lying around from the last one.
    func testAnAttemptThatHasNotAdvancedSharesNothing() {
        XCTAssertNil(ExportFlow.finishedExport(previousAttempt: 2, completedAttempt: 2, url: url))
        XCTAssertNil(ExportFlow.finishedExport(previousAttempt: 3, completedAttempt: 2, url: url))
    }
}
