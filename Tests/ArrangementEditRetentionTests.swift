import XCTest
@testable import Chiptune

/// Arrangement's Edit mode lives on the Studio, not in the view's own state,
/// so a pose change on the iPhone Duo (which swaps the sheet and the popover
/// and rebuilds the view) keeps it.
@MainActor
final class ArrangementEditRetentionTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Arr"))
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testEditModeIsKeptByTheStudio() {
        XCTAssertFalse(studio.editingArrangement)
        studio.setEditingArrangement(true)
        XCTAssertTrue(studio.editingArrangement)
    }

    func testEditingSectionsKeepsEditMode() {
        studio.setEditingArrangement(true)
        studio.addSection(patternID: studio.song.patterns[0].id)
        XCTAssertTrue(studio.editingArrangement)
    }

    func testDoneEndsEditMode() {
        studio.setEditingArrangement(true)
        studio.setEditingArrangement(false)
        XCTAssertFalse(studio.editingArrangement)
    }

    func testOpeningAnotherSongEndsEditMode() {
        studio.setEditingArrangement(true)
        studio.open(Song(name: "Other"))
        XCTAssertFalse(studio.editingArrangement)
    }
}
