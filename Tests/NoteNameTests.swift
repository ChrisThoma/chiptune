import XCTest
@testable import Chiptune

final class NoteNameTests: XCTestCase {

    func testOrdinaryPitchesLabelAsLetterAndOctave() {
        XCTAssertEqual(NoteName.label(60), "C4")
        XCTAssertEqual(NoteName.label(61), "C#4")
    }

    func testANoteOffLabelsAsRest() {
        // User-facing rename from "OFF": it reads like composing music
        // instead of flipping a switch. Chip.noteOff itself is unchanged.
        XCTAssertEqual(NoteName.label(Chip.noteOff), "REST")
    }

    func testAnEmptyNoteLabelsAsBlank() {
        XCTAssertEqual(NoteName.label(Chip.emptyNote), "")
    }
}
