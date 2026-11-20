import XCTest
import CoreGraphics
@testable import Chiptune

/// What a grid cell shows, says and offers for a note's pitch effect, in the
/// app and in the Grid video. The views only wire these helpers up; the
/// helpers are where the words live.
final class NoteEffectCellTests: XCTestCase {

    private let e5: Int8 = 76

    // MARK: Cell title and mark

    func testANoteShowsItsPlainNameAndCarriesItsEffectAsAMark() {
        XCTAssertEqual(GridCellText.title(note: e5, effect: .slideUp), "E5")
        XCTAssertEqual(GridCellText.mark(note: e5, effect: .slideUp), .slideUp)
        XCTAssertEqual(GridCellText.title(note: 61, effect: .vibrato), "C#4")
        XCTAssertEqual(GridCellText.mark(note: 61, effect: .vibrato), .vibrato)
    }

    func testANoteWithoutAnEffectHasNoMark() {
        XCTAssertEqual(GridCellText.title(note: e5, effect: .none), "E5")
        XCTAssertNil(GridCellText.mark(note: e5, effect: .none))
    }

    func testRestsAndEmptyStepsNeverCarryAMark() {
        XCTAssertEqual(GridCellText.title(note: Chip.noteOff, effect: .vibrato), "REST")
        XCTAssertNil(GridCellText.mark(note: Chip.noteOff, effect: .vibrato))
        XCTAssertEqual(GridCellText.title(note: Chip.emptyNote, effect: .slideDown), "·")
        XCTAssertNil(GridCellText.mark(note: Chip.emptyNote, effect: .slideDown))
    }

    // MARK: Mark geometry

    func testEveryEffectHasAMarkInsideItsBoxAndNoneHasNone() {
        XCTAssertNil(EffectMark.unitPath(.none))
        let box = CGRect(x: 0, y: 0, width: 1, height: 1)
        for effect in NoteEffect.allCases where effect != .none {
            guard let path = EffectMark.unitPath(effect) else { return XCTFail("\(effect)") }
            XCTAssertTrue(box.contains(path.boundingBoxOfPath), "\(effect)")
        }
    }

    func testAMarkedNoteFitsTheNarrowestPhoneColumnAtFullSize() {
        let available = ChipLayout.phone.gridMinColumnWidth - EffectMark.cellPadding
        XCTAssertEqual(EffectMark.fitScale(name: "C#5", effect: .slideUp, fontSize: 12, available: available), 1)
    }

    func testAMarkedNoteThatOverflowsShrinksNameAndMarkTogether() {
        let wide = EffectMark.labelWidth(name: "C#5", effect: .bendIn, fontSize: 30)
        let scale = EffectMark.fitScale(name: "C#5", effect: .bendIn, fontSize: 30, available: wide / 2)
        XCTAssertEqual(scale, 0.5, accuracy: 0.01)
        XCTAssertLessThanOrEqual(EffectMark.labelWidth(name: "C#5", effect: .bendIn, fontSize: 30 * scale),
                                 wide / 2 + 0.5)
    }

    func testTheMarkSitsOnTheBaselineAfterTheName() {
        let layout = EffectMark.layout(name: "E5", effect: .vibrato, fontSize: 12,
                                       in: CGRect(x: 0, y: 0, width: 70, height: 40))
        XCTAssertEqual(layout.markRect.maxY, layout.baseline, accuracy: 0.001)
        XCTAssertGreaterThan(layout.markRect.minX, layout.nameRect.minX)
        XCTAssertEqual(layout.nameRect.midX + layout.markRect.width / 2 + layout.gap / 2,
                       35, accuracy: 0.5, "name and mark centered together")
    }

    // MARK: VoiceOver

    func testTheSpokenValueNamesTheEffect() {
        XCTAssertEqual(GridCellText.accessibilityValue(note: e5, effect: .vibrato), "E5, Vibrato")
        XCTAssertEqual(GridCellText.accessibilityValue(note: e5, effect: .bendIn), "E5, Bend in")
    }

    func testTheSpokenValueOfAPlainNoteRestOrEmptyStepIsUnchanged() {
        XCTAssertEqual(GridCellText.accessibilityValue(note: e5, effect: .none), "E5")
        XCTAssertEqual(GridCellText.accessibilityValue(note: Chip.noteOff, effect: .glide), "REST")
        XCTAssertEqual(GridCellText.accessibilityValue(note: Chip.emptyNote, effect: .none), "Empty")
    }

    func testThereIsAnActionForEveryEffectAndForNone() {
        XCTAssertEqual(NoteEffect.allCases.map(GridCellText.actionName), [
            "No effect", "Effect: Slide up", "Effect: Slide down",
            "Effect: Vibrato", "Effect: Glide", "Effect: Bend in",
        ])
    }

    func testOnlyANoteOffersEffects() {
        XCTAssertTrue(GridCellText.offersEffects(note: e5))
        XCTAssertTrue(GridCellText.offersEffects(note: 0))
        XCTAssertFalse(GridCellText.offersEffects(note: Chip.noteOff))
        XCTAssertFalse(GridCellText.offersEffects(note: Chip.emptyNote))
    }

    // MARK: Video

    func testTheGridVideoDrawsTheSameLabelAndMark() {
        var pattern = Pattern(name: "A", trackCount: 2)
        pattern.rows[0][3] = e5
        pattern.setEffect(.vibrato, track: 0, step: 3)
        pattern.rows[1][3] = 60
        pattern.rows[1][4] = Chip.noteOff

        XCTAssertEqual(VideoFrameRenderer.cellLabel(pattern: pattern, track: 0, step: 3), "E5")
        XCTAssertEqual(VideoFrameRenderer.cellMark(pattern: pattern, track: 0, step: 3), .vibrato)
        XCTAssertNil(VideoFrameRenderer.cellMark(pattern: pattern, track: 1, step: 3))
        XCTAssertNil(VideoFrameRenderer.cellMark(pattern: pattern, track: 1, step: 4))
        XCTAssertEqual(VideoFrameRenderer.cellLabel(pattern: pattern, track: 1, step: 3), "C4")
        XCTAssertEqual(VideoFrameRenderer.cellLabel(pattern: pattern, track: 1, step: 4), "REST")
        XCTAssertEqual(VideoFrameRenderer.cellLabel(pattern: pattern, track: 0, step: 5), "·")
    }

    // MARK: Help

    func testTheHelpGuideExplainsEffectsAndTheirMidiExport() {
        let notes = HelpGuide.section(.notes)?.entries ?? []
        guard let entry = notes.first(where: { $0.term == "Effects" }) else {
            return XCTFail("No Effects entry in the Notes section")
        }
        let text = entry.text.lowercased()
        for word in ["hold", "slide", "vibrato", "glide", "bend", "midi"] {
            XCTAssertTrue(text.contains(word), word)
        }
    }
}
