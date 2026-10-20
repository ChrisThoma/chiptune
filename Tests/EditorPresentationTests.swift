import XCTest
@testable import Chiptune

/// Chords that change the song must not fire while a dialog, alert or sheet
/// holds state about the song as it was when it opened (#8): Cmd+N behind the
/// "Clear pattern B?" alert left it up over a different song.
final class EditorPresentationTests: XCTestCase {

    func testNothingPresentedAllowsSongCommands() {
        let presenters = SongBoundPresenters()
        XCTAssertFalse(presenters.isPresented)
        XCTAssertTrue(EditorPresentation.canChangeSong(songBoundPresented: presenters.isPresented))
    }

    func testEverySongBoundSurfaceBlocksSongCommands() {
        for surface in SongBoundPresenters.Surface.allCases {
            var presenters = SongBoundPresenters()
            presenters.set(surface, presented: true)
            XCTAssertTrue(presenters.isPresented, "\(surface)")
            XCTAssertFalse(EditorPresentation.canChangeSong(songBoundPresented: presenters.isPresented),
                           "\(surface)")
        }
    }

    func testCoversPatternDialogsTempoAlertAndTrackSound() {
        let all = Set(SongBoundPresenters.Surface.allCases)
        XCTAssertTrue(all.isSuperset(of: [.patternRename, .patternClear, .patternDelete,
                                          .tempoAlert, .trackSound]))
    }

    func testOneSurfaceClosingDoesNotClearAnother() {
        var presenters = SongBoundPresenters()
        presenters.set(.tempoAlert, presented: true)
        presenters.set(.trackSound, presented: true)
        presenters.set(.tempoAlert, presented: false)
        XCTAssertTrue(presenters.isPresented)
        presenters.set(.trackSound, presented: false)
        XCTAssertFalse(presenters.isPresented)
    }

    func testSettingTwiceIsIdempotent() {
        var presenters = SongBoundPresenters()
        presenters.set(.patternClear, presented: true)
        presenters.set(.patternClear, presented: true)
        presenters.set(.patternClear, presented: false)
        XCTAssertFalse(presenters.isPresented)
    }
}

/// The Cmd-hold overlay lists every chord; one that is blocked must show as
/// dimmed rather than enabled and do nothing when pressed.
final class EditorCommandEnabledTests: XCTestCase {

    func testEnabledOnlyWithAnEditorAndNothingSongBoundUp() {
        XCTAssertTrue(EditorPresentation.commandEnabled(hasEditor: true, canChangeSong: true))
    }

    func testDimmedWhileADialogOrSheetHoldsTheSong() {
        XCTAssertFalse(EditorPresentation.commandEnabled(hasEditor: true, canChangeSong: false))
    }

    func testDimmedWithNoEditor() {
        XCTAssertFalse(EditorPresentation.commandEnabled(hasEditor: false, canChangeSong: true))
    }
}

/// The menu rows read their enabled state from the scene value, and the
/// commands only re-evaluate when that value compares unequal. So the blocked
/// state has to be part of it: equal-by-studio alone meant a row dimmed under
/// a dialog could stay dimmed, and its chord dead, after the dialog closed.
@MainActor
final class EditorActionsSnapshotTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    private func actions(canChangeSong: Bool, now: @escaping () -> Bool = { true }) -> EditorActions {
        EditorActions(studio: studio, endRenaming: {}, openSongs: {}, openArrangement: {},
                      openExport: {}, confirmClearPattern: {},
                      canChangeSong: canChangeSong, canChangeSongNow: now)
    }

    func testADialogOpeningOrClosingChangesTheValue() {
        XCTAssertNotEqual(actions(canChangeSong: true), actions(canChangeSong: false))
    }

    func testSameStudioAndStateIsTheSameValue() {
        XCTAssertEqual(actions(canChangeSong: true), actions(canChangeSong: true))
        XCTAssertEqual(actions(canChangeSong: false), actions(canChangeSong: false))
    }

    func testRowsFollowTheSnapshot() {
        XCTAssertTrue(EditorPresentation.commandEnabled(editor: actions(canChangeSong: true)))
        XCTAssertFalse(EditorPresentation.commandEnabled(editor: actions(canChangeSong: false)))
        XCTAssertFalse(EditorPresentation.commandEnabled(editor: nil))
    }

    func testRowsDoNotReadTheLiveCheck() {
        // The live check is the action's guard. The rows must not call it, or
        // they'd go stale in exactly the way the snapshot is there to avoid.
        var calls = 0
        let editor = actions(canChangeSong: true, now: { calls += 1; return false })
        XCTAssertTrue(EditorPresentation.commandEnabled(editor: editor))
        XCTAssertEqual(calls, 0)
    }

    /// The docked instrument editor owns its own Clear track and Delete track
    /// alerts, and the grid reports nothing for them while docked (#1).
    func testTrackClearAndDeleteAlertsAreSongBound() {
        let all = Set(SongBoundPresenters.Surface.allCases)
        XCTAssertTrue(all.isSuperset(of: [.trackClear, .trackDelete]))
        for surface in [SongBoundPresenters.Surface.trackClear, .trackDelete] {
            var presenters = SongBoundPresenters()
            presenters.set(surface, presented: true)
            XCTAssertFalse(EditorPresentation.canChangeSong(songBoundPresented: presenters.isPresented),
                           "\(surface)")
        }
    }
}
