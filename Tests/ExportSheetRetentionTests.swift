import XCTest
@testable import Chiptune

/// The Export sheet's Repeats row had the same system `Stepper` ARR did, so
/// every open and close of Export kept a `UIStepper` and its hosted graph
/// alive the same way.
@MainActor
final class ExportSheetRetentionTests: XCTestCase {

    func testClosingExportLeavesNoViewsAlive() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        defer { studio.invalidateTimers() }
        studio.open(TestSongs.golden())

        try assertClosingLeavesNoViewsAlive(ExportSheet(studio: studio))
    }
}
