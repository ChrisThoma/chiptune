import XCTest
@testable import Chiptune

/// What VoiceOver hears while a render runs. A video can take a minute, and
/// a bar that only changes on screen says nothing to someone who can't see it.
final class ExportAnnouncementTests: XCTestCase {

    func testTheStartSaysWhatIsBeingExported() {
        XCTAssertEqual(ExportAnnouncement.started(format: .video), "Exporting video")
        XCTAssertEqual(ExportAnnouncement.started(format: .wav), "Exporting")
        XCTAssertEqual(ExportAnnouncement.started(format: .midi), "Exporting")
    }

    func testACancelSaysSo() {
        XCTAssertEqual(ExportAnnouncement.canceled, "Export canceled")
    }

    func testEachQuarterIsAnnouncedOnceAsItIsCrossed() {
        XCTAssertNil(ExportAnnouncement.milestone(from: 0, to: 0.1))
        XCTAssertEqual(ExportAnnouncement.milestone(from: 0.24, to: 0.25), "25%")
        XCTAssertNil(ExportAnnouncement.milestone(from: 0.25, to: 0.3), "already said")
        XCTAssertEqual(ExportAnnouncement.milestone(from: 0.49, to: 0.51), "50%")
        XCTAssertEqual(ExportAnnouncement.milestone(from: 0.7, to: 0.76), "75%")
        XCTAssertNil(ExportAnnouncement.milestone(from: 0.76, to: 1), "the end is the share sheet, not a number")
    }

    /// Once Cancel export is tapped, the render can still cross a quarter
    /// before it notices. "50%" after the user asked it to stop is wrong.
    func testNoMilestoneAfterCancelIsTapped() {
        var render = ExportAnnouncement.Render()
        XCTAssertEqual(render.milestone(from: 0.2, to: 0.3), "25%")
        render.cancelTapped()
        XCTAssertNil(render.milestone(from: 0.45, to: 0.55))
    }

    /// "Export canceled" is said when the render ends canceled, not on the
    /// tap: a render that finishes anyway made a file, and says nothing more.
    func testCanceledIsSaidOnlyWhenTheRenderEndsCanceled() {
        XCTAssertEqual(ExportAnnouncement.Render.ended(canceled: true), "Export canceled")
        XCTAssertNil(ExportAnnouncement.Render.ended(canceled: false))
    }

    /// A new render starts with milestones on again.
    func testANewRenderAnnouncesMilestonesAgain() {
        var render = ExportAnnouncement.Render()
        render.cancelTapped()
        render = ExportAnnouncement.Render()
        XCTAssertEqual(render.milestone(from: 0.2, to: 0.3), "25%")
    }

    /// Progress that jumps past several quarters says only where it is now.
    func testAJumpSaysTheLatestQuarter() {
        XCTAssertEqual(ExportAnnouncement.milestone(from: 0.1, to: 0.8), "75%")
    }

    /// The bar resets to 0 when a render ends; that's not progress.
    func testGoingBackwardsSaysNothing() {
        XCTAssertNil(ExportAnnouncement.milestone(from: 0.8, to: 0))
    }

    func testTheProgressRowReadsAsOneElementWithAPercentage() {
        XCTAssertEqual(ExportAnnouncement.started(format: .video), "Exporting video")
        XCTAssertEqual(ExportAnnouncement.progressValue(format: .video, progress: 0.42), "42%")
        XCTAssertEqual(ExportAnnouncement.progressValue(format: .wav, progress: 0.5), "50%")
        // A MIDI export reports no progress.
        XCTAssertNil(ExportAnnouncement.progressValue(format: .midi, progress: 0))
    }
}
