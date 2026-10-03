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
