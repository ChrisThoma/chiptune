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
    private let song = UUID()

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
        let step = ExportFlow.afterExportClosed(pendingShare: false)
        XCTAssertFalse(step.shareNow)
        XCTAssertFalse(step.closeExport)
        XCTAssertFalse(step.shareWhenExportCloses)
    }

    // MARK: When the export options go back to the defaults

    /// Closing the panel by hand ends the export, so the next one starts at
    /// WAV, 1x, Seamless loop.
    func testPanelClosedByHandEndsTheFlow() {
        XCTAssertTrue(ExportFlow.afterExportClosed(pendingShare: false).endsFlow)
    }

    /// Closing for the share sheet doesn't: a canceled share brings the panel
    /// back, and it should still show what was picked.
    func testPanelClosedForTheShareSheetKeepsTheFlowGoing() {
        XCTAssertFalse(ExportFlow.afterExportClosed(pendingShare: true).endsFlow)
    }

    func testACanceledShareKeepsTheFlowGoing() {
        XCTAssertFalse(ExportFlow.endsFlowAfterShare(outcome: .canceled, sharedSongID: song, currentSongID: song))
    }

    func testACompletedOrFailedShareEndsTheFlow() {
        XCTAssertTrue(ExportFlow.endsFlowAfterShare(outcome: .completed, sharedSongID: song, currentSongID: song))
        XCTAssertTrue(ExportFlow.endsFlowAfterShare(outcome: .failed, sharedSongID: song, currentSongID: song))
    }

    /// Don't Allow on Save Video fails the share, but the Photos alert is
    /// offering to share the same video again after Settings. Ending the
    /// flow there put the options back to WAV, 1x, so backing out of the
    /// retried share reopened Export on the wrong format.
    func testAFailedShareWithAPhotosRetryOfferedKeepsTheFlowGoing() {
        XCTAssertFalse(ExportFlow.endsFlowAfterShare(outcome: .failed, sharedSongID: song, currentSongID: song,
                                                     photosRetryOffered: true))
    }

    /// The panel still stays shut: the Photos alert is what's on screen.
    func testAFailedShareWithAPhotosRetryOfferedLeavesTheExportPanelClosed() {
        XCTAssertFalse(ExportFlow.reopensExportAfterShare(outcome: .failed, sharedSongID: song, currentSongID: song))
    }

    /// OK on the Photos alert drops the retry, and with it the export.
    /// Open Settings keeps both until the user is back.
    func testThePhotosAlertEndsTheFlowOnlyWhenTheRetryIsDropped() {
        XCTAssertTrue(ExportFlow.endsFlowAfterPhotosAlert(openedSettings: false))
        XCTAssertFalse(ExportFlow.endsFlowAfterPhotosAlert(openedSettings: true))
    }

    /// Back from Settings: a reshare carries on the export, and a retry that
    /// can't be offered any more ends it.
    func testARetryThatCantReshareEndsTheFlow() {
        XCTAssertTrue(ExportFlow.endsFlowAfterPhotosRetry(reshares: false))
        XCTAssertFalse(ExportFlow.endsFlowAfterPhotosRetry(reshares: true))
    }

    /// The Close button pairs a cancel with its dismiss, but a swipe-to-dismiss
    /// or an outside tap on the popover reaches `onDisappear` with no cancel
    /// having happened. A render still in flight at that point must not be
    /// left to finish unobserved — its eventual error would have nowhere left
    /// to be shown.
    func testPanelDisappearingMidRenderAsksForACancel() {
        XCTAssertTrue(ExportFlow.afterPanelDisappeared(isExporting: true))
    }

    /// A pose change flips the size class and SwiftUI rebuilds the popover or
    /// sheet: `onDisappear` fires while the presentation flag is still on and
    /// a new panel appears. That is not a close, so the render carries on and
    /// nothing is cancelled or reset.
    func testPanelRebuiltMidRenderIsNotACloseAndKeepsTheRender() {
        XCTAssertTrue(ExportFlow.panelRebuilt(stillPresented: true))
        XCTAssertFalse(ExportFlow.afterPanelDisappeared(isExporting: true, stillPresented: true))
    }

    /// A rebuild with no render running (the options are only chosen, nothing
    /// exporting) is just as little a close: the flag is still on, so the
    /// export flow must not end and the chosen options stay.
    func testPanelRebuiltWhileIdleIsNotACloseAndKeepsTheOptions() {
        XCTAssertTrue(ExportFlow.panelRebuilt(stillPresented: true))
    }

    /// A close by hand (flag already off) mid-render still cancels, and a
    /// panel going away with its flag off is not a rebuild.
    func testPanelClosedByHandMidRenderStillCancels() {
        XCTAssertFalse(ExportFlow.panelRebuilt(stillPresented: false))
        XCTAssertTrue(ExportFlow.afterPanelDisappeared(isExporting: true, stillPresented: false))
    }

    /// The panel disappearing because the render already finished — success or
    /// failure — must not re-cancel a render that isn't running.
    func testPanelDisappearingAfterTheRenderFinishedAsksForNothing() {
        XCTAssertFalse(ExportFlow.afterPanelDisappeared(isExporting: false))
    }

    /// Backing out of the share sheet without sharing is "let me try another
    /// ending", so the panel comes back for it.
    func testCanceledShareReturnsToTheExportPanel() {
        XCTAssertTrue(ExportFlow.reopensExportAfterShare(outcome: .canceled, sharedSongID: song, currentSongID: song))
    }

    /// The file went somewhere; the job is done.
    func testCompletedShareLeavesTheExportPanelClosed() {
        XCTAssertFalse(ExportFlow.reopensExportAfterShare(outcome: .completed, sharedSongID: song, currentSongID: song))
    }

    /// A failed share is already raising its own alert, which a popover
    /// coming up underneath would fight for the screen.
    func testFailedShareLeavesTheExportPanelClosed() {
        XCTAssertFalse(ExportFlow.reopensExportAfterShare(outcome: .failed, sharedSongID: song, currentSongID: song))
    }

    /// A .chipsong opened from another app while the share sheet was up
    /// swaps the song underneath it. Backing out of the share then brought
    /// the Export panel up over the new song, holding the old one's
    /// options: the new song never asked to be exported.
    func testACanceledShareOfASongNoLongerOpenLeavesTheExportPanelClosed() {
        XCTAssertFalse(ExportFlow.reopensExportAfterShare(outcome: .canceled,
                                                          sharedSongID: song, currentSongID: UUID()))
    }

    /// With the panel staying shut, the old song's options go back to the
    /// defaults rather than waiting for the next export to pick them up.
    func testACanceledShareOfASongNoLongerOpenEndsTheFlow() {
        XCTAssertTrue(ExportFlow.endsFlowAfterShare(outcome: .canceled,
                                                    sharedSongID: song, currentSongID: UUID()))
    }

    /// No song recorded for the share means nothing to return to.
    func testACanceledShareWithNoSongRecordedLeavesTheExportPanelClosed() {
        XCTAssertFalse(ExportFlow.reopensExportAfterShare(outcome: .canceled,
                                                          sharedSongID: nil, currentSongID: song))
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

/// The share sheet ends with two callbacks UIKit doesn't order: SwiftUI's
/// `onDismiss` and the activity controller's completion handler. Saving a
/// first video to Photos puts up the permission prompt, and after Allow the
/// dismissal arrives first, so deciding on it alone read the share as
/// canceled: the Export panel came back and the review prompt went uncounted.
final class ShareSheetEndingTests: XCTestCase {

    func testDismissalBeforeTheCompletionWaitsForIt() {
        var ending = ShareSheetEnding()
        XCTAssertNil(ending.sheetDismissed(), "the outcome isn't known yet")
        XCTAssertEqual(ending.activityFinished(.completed), .completed)
    }

    func testCompletionBeforeTheDismissalWaitsForIt() {
        var ending = ShareSheetEnding()
        XCTAssertNil(ending.activityFinished(.completed), "the sheet is still on screen")
        XCTAssertEqual(ending.sheetDismissed(), .completed)
    }

    func testACancelIsDecidedEitherWay() {
        var first = ShareSheetEnding()
        XCTAssertNil(first.sheetDismissed())
        XCTAssertEqual(first.activityFinished(.canceled), .canceled)
        var second = ShareSheetEnding()
        XCTAssertNil(second.activityFinished(.failed))
        XCTAssertEqual(second.sheetDismissed(), .failed)
    }

    /// One share ends once: a late or repeated callback decides nothing more.
    func testTheShareIsDecidedOnlyOnce() {
        var ending = ShareSheetEnding()
        XCTAssertNil(ending.activityFinished(.completed))
        XCTAssertEqual(ending.sheetDismissed(), .completed)
        XCTAssertNil(ending.activityFinished(.canceled))
        XCTAssertNil(ending.sheetDismissed())
    }

    /// An activity backed out of (a Mail draft canceled, say) leaves the
    /// sheet up, and what the user does next is what counts.
    /// A different song opening takes the sheet down from the app's side,
    /// and `UIActivityViewController` may then never report at all. With
    /// nothing reported, that ending is a cancel, decided right there.
    func testTheAppClosingTheSheetWithNoReportIsACancel() {
        var ending = ShareSheetEnding()
        XCTAssertEqual(ending.sheetClosedByApp(), .canceled)
        XCTAssertNil(ending.sheetDismissed(), "SwiftUI's own dismissal comes after and decides nothing more")
        XCTAssertNil(ending.activityFinished(.completed))
    }

    /// The activity had already reported (a save that finished, say): that
    /// is still what happened.
    func testTheAppClosingTheSheetKeepsAReportedOutcome() {
        var ending = ShareSheetEnding()
        XCTAssertNil(ending.activityFinished(.completed))
        XCTAssertEqual(ending.sheetClosedByApp(), .completed)
    }

    func testTheAppClosingADecidedShareDecidesNothing() {
        var ending = ShareSheetEnding()
        XCTAssertNil(ending.activityFinished(.canceled))
        XCTAssertEqual(ending.sheetDismissed(), .canceled)
        XCTAssertNil(ending.sheetClosedByApp())
    }

    func testTheLastCompletionBeforeTheDismissalCounts() {
        var ending = ShareSheetEnding()
        XCTAssertNil(ending.activityFinished(.canceled))
        XCTAssertNil(ending.activityFinished(.completed))
        XCTAssertEqual(ending.sheetDismissed(), .completed)
    }
}
