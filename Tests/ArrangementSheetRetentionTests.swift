import XCTest
@testable import Chiptune

/// Opening and closing the ARR sheet kept ~0.15 MB alive every time, without
/// end. The sheet's own controller and graph went away; what stayed was the
/// rows' system `Stepper` — on iOS 26 a `UIStepper` drawing through its own
/// hosted SwiftUI graph, which UIKit never releases once it is torn down.
///
/// Presents the arrangement the way a phone does, dismisses it, and checks
/// that no view it put on screen is still alive.
@MainActor
final class ArrangementSheetRetentionTests: XCTestCase {

    func testClosingTheArrangementLeavesNoViewsAlive() throws {
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        defer { studio.invalidateTimers() }
        studio.open(Song(name: "Blank"))
        studio.addPattern()
        studio.addSection(patternID: studio.song.patterns[0].id)   // three rows

        try assertClosingLeavesNoViewsAlive(ArrangementView(studio: studio))
    }
}
