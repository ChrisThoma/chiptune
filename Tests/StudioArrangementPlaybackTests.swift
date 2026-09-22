import XCTest
@testable import Chiptune

/// Editing the arrangement while the song plays.
///
/// Sibling of `StudioPlayheadTests`' re-indexing section: there the pattern
/// list was renumbered under the sequencer, here the chain is. Adding,
/// removing or moving a section rewrites every slot number after it, and the
/// core holds its place in the chain as a raw slot index, so the section that
/// was sounding has to be found again by identity after the edit.
///
/// The fixture is the reported one: A x4, C x3, D x8, with the cursor part way
/// through C's repeats.
@MainActor
final class StudioArrangementPlaybackTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Blank"))
        studio.addPattern()              // A, C, D — one section each
        studio.addPattern()
        studio.selectPattern(0)
        studio.song.arrangement[0].repeats = 4
        studio.song.arrangement[1].repeats = 3
        studio.song.arrangement[2].repeats = 8
        studio.pushArrangement()
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    // MARK: Driving the core

    private func samplesPerStep(tempo: Double) -> Int {
        Int((RenderHarness.sampleRate * 60.0 / (tempo * 4.0)).rounded())
    }

    /// `play()` needs a live `AVAudioEngine`; this is the part of it the
    /// sequencer cares about, done straight to the core.
    private func startSongPlayback() {
        studio.songMode = true
        studio.isPlaying = true
        studio.pushAll()
        studio.engine.core.setSongMode(true)
        studio.engine.core.start()
        _ = RenderHarness.renderMono(studio.engine.core, frames: 1)
    }

    /// Renders `steps` steps and then feeds the core's position to the studio
    /// the way the 60 Hz timer does.
    private func advance(steps: Int) {
        let frames = samplesPerStep(tempo: studio.song.tempo) * steps
        _ = RenderHarness.renderMono(studio.engine.core, frames: frames)
        let core = studio.engine.core
        studio.applyPlayhead(step: Int(core.currentStep),
                             pattern: Int(core.currentPattern),
                             slot: Int(core.currentChainSlot))
    }

    /// Plays up to slot 4 — the first of C's three repeats — and returns C's
    /// pattern id so the assertions can name it after the edit.
    @discardableResult
    private func soundC() -> UUID {
        startSongPlayback()
        XCTAssertEqual(studio.song.chain, [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2],
                       "the test's premise")
        advance(steps: 4 * 16)           // four plays of A, then C's first
        XCTAssertEqual(studio.engine.core.currentChainSlot, 4, "precondition: C's first repeat")
        XCTAssertEqual(studio.engine.core.currentPattern, 1, "precondition: C is sounding")
        return studio.song.patterns[1].id
    }

    /// The section holding `id`, and where its slots start.
    private func slotStart(ofPattern id: UUID) -> Int? {
        guard let section = studio.song.arrangement.firstIndex(where: { $0.patternID == id }) else { return nil }
        return studio.song.chainStart(ofSection: section)
    }

    // MARK: Tests

    /// The reported bug. Deleting A takes four slots out of the chain, so the
    /// slot C was sounding from now belongs to D and playback jumped there at
    /// the next boundary instead of finishing C's remaining repeats.
    func testDeletingAnEarlierSectionKeepsTheSoundingSectionPlaying() {
        let soundingID = soundC()

        studio.removeSection(at: IndexSet(integer: 0))

        XCTAssertEqual(studio.song.chain, [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2])
        XCTAssertEqual(slotStart(ofPattern: soundingID), 0, "premise: C's section moved to slot 0")
        XCTAssertEqual(studio.engine.core.currentChainSlot, 0, "C's first repeat, renumbered")
        XCTAssertEqual(studio.engine.core.currentPattern, 1, "the same pattern must keep sounding")
        XCTAssertEqual(studio.playingPattern, 1)
    }

    /// Same edit, deeper into the repeats: the cursor must keep its place
    /// among them rather than restarting the section.
    func testDeletingAnEarlierSectionKeepsTheOffsetWithinTheRepeats() {
        let soundingID = soundC()
        advance(steps: 16)               // C's second repeat
        XCTAssertEqual(studio.engine.core.currentChainSlot, 5, "precondition")

        studio.removeSection(at: IndexSet(integer: 0))

        XCTAssertEqual(slotStart(ofPattern: soundingID), 0, "premise")
        XCTAssertEqual(studio.engine.core.currentChainSlot, 1, "still the section's second play")
        XCTAssertEqual(studio.engine.core.currentPattern, 1)
        XCTAssertEqual(studio.playingPattern, 1)
    }

    /// Dragging D to the top pushes C's slots eight later.
    func testMovingASectionKeepsTheSoundingSectionPlaying() {
        let soundingID = soundC()

        studio.moveSection(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(studio.song.chain, [2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 1, 1, 1])
        XCTAssertEqual(slotStart(ofPattern: soundingID), 12, "premise: C's section moved down")
        XCTAssertEqual(studio.engine.core.currentChainSlot, 12, "C's first repeat, renumbered")
        XCTAssertEqual(studio.engine.core.currentPattern, 1)
        XCTAssertEqual(studio.playingPattern, 1)
    }

    /// Repointing another section at a different pattern leaves the chain the
    /// same length, so the cursor has nowhere to go — asserted so the restore
    /// can't quietly move it.
    func testRepointingAnotherSectionLeavesTheCursorAlone() {
        soundC()
        let target = studio.song.arrangement[0].id

        studio.setSection(target, patternID: studio.song.patterns[2].id)

        XCTAssertEqual(studio.engine.core.currentChainSlot, 4)
        XCTAssertEqual(studio.engine.core.currentPattern, 1)
        XCTAssertEqual(studio.playingPattern, 1)
    }

    /// Appending a section adds slots after the cursor, which likewise must
    /// not disturb it.
    func testAppendingASectionLeavesTheCursorAlone() {
        soundC()

        studio.addSection(patternID: studio.song.patterns[0].id)

        XCTAssertEqual(studio.engine.core.currentChainSlot, 4)
        XCTAssertEqual(studio.engine.core.currentPattern, 1)
        XCTAssertEqual(studio.playingPattern, 1)
    }
}
