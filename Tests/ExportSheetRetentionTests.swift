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

    /// The segmented format picker is a UIKit control; the MIDI layout drops
    /// the stepper and the Ending picker around it.
    func testClosingExportInMidiLeavesNoViewsAlive() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        defer { studio.invalidateTimers() }
        studio.open(TestSongs.golden())
        studio.exportOptions.format = .midi

        try assertClosingLeavesNoViewsAlive(ExportSheet(studio: studio))
    }
}
