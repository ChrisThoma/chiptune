import XCTest
@testable import Chiptune

/// Round-5 #4: editing the arrangement while SONG plays has to keep the
/// sounding section sounding (same section instance, same play-through,
/// repeats clamped), and when the sounding section itself goes, the next
/// section takes over, with the grid following unless pinned.
///
/// Fixture: patterns A (16 steps), B (32), C (8), D (16); arrangement
/// A x2, B x2, C x1, D x2, so the chain is [A A B B C D D].
@MainActor
final class StudioArrangementEditWhilePlayingTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!
    private var ids: [UUID] = []

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Blank"))
        studio.addPattern()
        studio.addPattern()
        studio.addPattern()
        let lengths = [16, 32, 8, 16]
        let repeats = [2, 2, 1, 2]
        for i in 0..<4 {
            studio.song.patterns[i].length = lengths[i]
            studio.song.arrangement[i].repeats = repeats[i]
        }
        ids = studio.song.patterns.map(\.id)
        studio.selectPattern(0)
        studio.pushAll()
        studio.pushArrangement()
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    // MARK: Driving the core

    private func stepFrames() -> Int {
        Int((RenderHarness.sampleRate * 60.0 / (studio.song.tempo * 4.0)).rounded())
    }

    private func startSongPlayback() {
        studio.songMode = true
        studio.isPlaying = true
        studio.pushAll()
        studio.engine.core.setSongMode(true)
        studio.armSongFollow()
        studio.engine.core.start()
        _ = RenderHarness.renderMono(studio.engine.core, frames: 1)
    }

    private func advance(steps: Int) {
        _ = RenderHarness.renderMono(studio.engine.core, frames: stepFrames() * steps)
        tick()
    }

    private func tick() {
        let core = studio.engine.core
        studio.applyPlayhead(step: Int(core.currentStep),
                             pattern: Int(core.currentPattern),
                             slot: Int(core.currentChainSlot))
    }

    /// Plays until the core is on `slot`, a couple of steps in.
    private func play(toSlot slot: Int) {
        startSongPlayback()
        var guardCount = 0
        while Int(studio.engine.core.currentChainSlot) != slot, guardCount < 400 {
            advance(steps: 1)
            guardCount += 1
        }
        advance(steps: 2)
        XCTAssertEqual(Int(studio.engine.core.currentChainSlot), slot, "precondition")
    }

    private func index(_ n: Int) -> Int { studio.song.patternIndex(id: ids[n])! }

    /// Everything that can disagree about "what sounds" must agree.
    private func assertSounding(slot: Int, pattern n: Int, section: Int,
                                gridFollows: Bool = true, _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let core = studio.engine.core
        XCTAssertEqual(Int(core.currentChainSlot), slot, "\(message): core slot", file: file, line: line)
        XCTAssertEqual(Int(core.currentPattern), index(n), "\(message): core pattern", file: file, line: line)
        XCTAssertEqual(studio.song.chain[safe: slot], index(n), "\(message): slot names that pattern", file: file, line: line)
        XCTAssertEqual(studio.playingPattern, index(n), "\(message): dot", file: file, line: line)
        XCTAssertEqual(studio.playingSection, section, "\(message): marker", file: file, line: line)
        if gridFollows {
            XCTAssertEqual(studio.selectedPattern, index(n), "\(message): grid", file: file, line: line)
        }
        // And it stays that way once the audio thread runs on.
        advance(steps: 1)
        XCTAssertEqual(studio.playingPattern, index(n), "\(message): dot after a step", file: file, line: line)
        XCTAssertEqual(studio.playingSection, section, "\(message): marker after a step", file: file, line: line)
        if gridFollows {
            XCTAssertEqual(studio.selectedPattern, index(n), "\(message): grid after a step", file: file, line: line)
        }
    }

    private func sectionIndex(_ n: Int) -> Int {
        studio.song.arrangement.firstIndex { $0.patternID == ids[n] }!
    }

    // MARK: Symptom 1: deleting the sounding section

    func testDeletingTheSoundingSectionHandsOverToTheNextSection() {
        play(toSlot: 3)                                     // B's second pass
        studio.removeSection(at: IndexSet(integer: 1))      // A A C D D
        XCTAssertEqual(studio.song.chain.count, 5, "premise")
        assertSounding(slot: 2, pattern: 2, section: 1, "after delete")
        XCTAssertTrue(studio.followsArrangement)
    }

    func testDeletingTheSoundingSectionThenUndoAndRedo() {
        play(toSlot: 3)
        studio.removeSection(at: IndexSet(integer: 1))
        studio.undo()
        // C keeps sounding in the restored arrangement.
        assertSounding(slot: 4, pattern: 2, section: 2, gridFollows: false, "after undo")
        studio.redo()
        assertSounding(slot: 2, pattern: 2, section: 1, gridFollows: false, "after redo")
    }

    func testDeletingTheSoundingSectionKeepsAPinnedGridPinned() {
        play(toSlot: 3)
        studio.selectPattern(0)                             // pin on A
        studio.removeSection(at: IndexSet(integer: 1))
        assertSounding(slot: 2, pattern: 2, section: 1, gridFollows: false, "pinned delete")
        XCTAssertEqual(studio.selectedPattern, index(0))
        XCTAssertFalse(studio.followsArrangement)
        studio.undo()
        assertSounding(slot: 4, pattern: 2, section: 2, gridFollows: false, "pinned undo")
        XCTAssertTrue(studio.song.chain.contains(studio.selectedPattern), "grid not left in no section")
        studio.redo()
        assertSounding(slot: 2, pattern: 2, section: 1, gridFollows: false, "pinned redo")
        XCTAssertTrue(studio.song.chain.contains(studio.selectedPattern), "grid not left in no section")
    }

    func testDeletingTheSoundingLastSectionWrapsToTheHead() {
        play(toSlot: 5)                                     // D's first pass
        studio.removeSection(at: IndexSet(integer: 3))      // A A B B C
        assertSounding(slot: 0, pattern: 0, section: 0, "wrap to head")
    }

    func testDeletingTheSoundingSectionWhoseOtherSectionSharesItsPattern() {
        // A A B B C D D plus a second B section at the end: deleting the
        // sounding B hands over to C, not to the other B.
        studio.addSection(patternID: ids[1])
        play(toSlot: 3)
        studio.removeSection(at: IndexSet(integer: 1))      // A A C D D B B
        assertSounding(slot: 2, pattern: 2, section: 1, "next section, not a twin")
    }

    // MARK: Symptom 2: deleting a section before the sounding one

    func testDeletingAnEarlierSectionKeepsTheSoundingSection() {
        play(toSlot: 4)                                     // C
        studio.removeSection(at: IndexSet(integer: 0))      // B B C D D
        assertSounding(slot: 2, pattern: 2, section: 1, "after delete")
    }

    func testDeletingAnEarlierSectionThenUndoAndRedo() {
        play(toSlot: 4)
        studio.removeSection(at: IndexSet(integer: 0))
        studio.undo()
        assertSounding(slot: 4, pattern: 2, section: 2, gridFollows: false, "after undo")
        studio.redo()
        assertSounding(slot: 2, pattern: 2, section: 1, gridFollows: false, "after redo")
    }

    func testDeletingAnEarlierSectionKeepsTheRepeatPositionOfTheSoundingOne() {
        play(toSlot: 3)                                     // B's second pass
        studio.removeSection(at: IndexSet(integer: 0))      // B B C D D
        assertSounding(slot: 1, pattern: 1, section: 0, "second pass kept")
    }

    // MARK: Symptom 3: repeats of another section

    func testRaisingAnEarlierSectionsRepeatsKeepsTheSoundingSection() {
        play(toSlot: 3)                                     // B's second pass
        let a = studio.song.arrangement[0].id
        studio.setSection(a, repeats: 3)
        studio.setSection(a, repeats: 4)
        assertSounding(slot: 5, pattern: 1, section: 1, "after raise")
        studio.undo()                                       // coalesced: back to 2
        assertSounding(slot: 3, pattern: 1, section: 1, "after undo")
        studio.redo()
        assertSounding(slot: 5, pattern: 1, section: 1, gridFollows: false, "after redo")
    }

    func testLoweringTheSoundingSectionsRepeatsClampsTheRepeatPosition() {
        play(toSlot: 3)                                     // B's second pass
        studio.setSection(studio.song.arrangement[1].id, repeats: 1)
        assertSounding(slot: 2, pattern: 1, section: 1, "clamped to the only pass")
    }

    func testRaisingTheSoundingSectionsRepeatsKeepsItsPass() {
        play(toSlot: 3)
        studio.setSection(studio.song.arrangement[1].id, repeats: 4)
        assertSounding(slot: 3, pattern: 1, section: 1, "same pass of more")
    }

    func testRaisingRepeatsKeepsAPinnedGridPinned() {
        play(toSlot: 3)
        studio.selectPattern(3)                             // pin on D
        studio.setSection(studio.song.arrangement[0].id, repeats: 4)
        assertSounding(slot: 5, pattern: 1, section: 1, gridFollows: false, "pinned raise")
        XCTAssertEqual(studio.selectedPattern, index(3))
    }

    // MARK: Reorder, repoint, append

    func testMovingASectionKeepsTheSoundingSectionAndUndoRedo() {
        play(toSlot: 4)                                     // C
        studio.moveSection(from: IndexSet(integer: 3), to: 0)   // D A B C -> D D A A B B C
        assertSounding(slot: 6, pattern: 2, section: 3, "after move")
        studio.undo()
        assertSounding(slot: 4, pattern: 2, section: 2, gridFollows: false, "after undo")
        studio.redo()
        assertSounding(slot: 6, pattern: 2, section: 3, gridFollows: false, "after redo")
    }

    func testRepointingTheSoundingSectionMovesTheCoreToItsNewPattern() {
        play(toSlot: 3)                                     // B's second pass
        studio.setSection(studio.song.arrangement[1].id, patternID: ids[2])
        assertSounding(slot: 3, pattern: 2, section: 1, "after repoint")
        studio.undo()
        assertSounding(slot: 3, pattern: 1, section: 1, gridFollows: false, "after undo")
        studio.redo()
        assertSounding(slot: 3, pattern: 2, section: 1, gridFollows: false, "after redo")
    }

    func testAppendingASectionLeavesPlaybackAlone() {
        play(toSlot: 3)
        studio.addSection(patternID: ids[0])
        assertSounding(slot: 3, pattern: 1, section: 1, "after append")
        studio.undo()
        assertSounding(slot: 3, pattern: 1, section: 1, gridFollows: false, "after undo")
    }
}
