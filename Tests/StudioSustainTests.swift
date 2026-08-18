import XCTest
@testable import Chiptune

/// A sustaining voice has nothing of its own to stop it — no decay runs out, no
/// pattern step comes along. Erasing the note that started it used to leave it
/// ringing at full level until STOP, which a playtester found within minutes:
/// "even [when] you remove all the tiles, the sound still goes."
///
/// These drive the real `Studio` edit methods and render its real core offline,
/// so they cover the whole path a tap takes — grid cell to model to DSP.
@MainActor
final class StudioSustainTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    private let sampleRate = RenderHarness.sampleRate

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

    /// One sustaining triangle, one note on step 0, nothing else. At 120 BPM a
    /// step is ~0.125 s, so the windows below all sit inside the first pass —
    /// the loop doesn't come back around to retrigger step 0 for two seconds.
    private func openHeldNote(extraNoteAt step: Int? = nil) {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .triangle)]
        song.tracks[0].instrument.sustain = true
        song.tracks[0].instrument.volume = 1.0
        song.patterns[0].rows = [Pattern.emptyRow]
        song.patterns[0].rows[0][0] = 48
        if let step { song.patterns[0].rows[0][step] = 60 }
        studio.open(song)
        studio.engine.core.start()
    }

    private func render(seconds: Double) -> [Float] {
        RenderHarness.renderMono(studio.engine.core, frames: Int(sampleRate * seconds))
    }

    /// The playtester's report, as an assertion.
    func testClearingTheNoteThatStartedARingingVoiceCutsIt() {
        openHeldNote()

        let before = render(seconds: 0.5)
        XCTAssertGreaterThan(RenderHarness.rms(before[(before.count - 4410)...]), 0.01,
                             "the held note should still be sounding before the edit")

        studio.setNote(track: 0, step: 0, note: Chip.emptyNote)

        // The release is specified at ~15 ms, so 0.2 s is generous.
        let after = render(seconds: 0.2)
        XCTAssertLessThan(RenderHarness.rms(after[(after.count - 4410)...]), 0.01,
                          "erasing the note that started it left the voice ringing")
    }

    /// The guard on the fix above: a release must be aimed at the cell that
    /// actually started the note. Cutting on any edit to the track would kill a
    /// held bass the moment you tidied up a later step.
    func testClearingAnUnrelatedStepLeavesTheRingingVoiceAlone() {
        openHeldNote(extraNoteAt: 8)

        let before = render(seconds: 0.5)
        XCTAssertGreaterThan(RenderHarness.rms(before[(before.count - 4410)...]), 0.01)

        // Step 8 is still a second away — the voice ringing now came from step 0.
        studio.setNote(track: 0, step: 8, note: Chip.emptyNote)

        let after = render(seconds: 0.2)
        XCTAssertGreaterThan(RenderHarness.rms(after[(after.count - 4410)...]), 0.01,
                             "clearing an unrelated step cut a voice it had nothing to do with")
    }

    func testClearingTheWholeTrackCutsIt() {
        openHeldNote()
        _ = render(seconds: 0.5)

        studio.clearTrack(0)

        XCTAssertLessThan(RenderHarness.rms(render(seconds: 0.2)[4410...]), 0.01,
                          "clearing the track left its held note ringing")
    }

    /// Clearing pattern B is not a reason to cut a note that came from A —
    /// the arrangement can be playing one while you tidy the other.
    func testClearPatternOnlyCutsVoicesFromThatPattern() {
        // Both patterns exist before playback starts. Adding one mid-test would
        // move the editor's focus onto it, and PATT mode follows the focus — so
        // the note under test would never be reached.
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .triangle)]
        song.tracks[0].instrument.sustain = true
        song.tracks[0].instrument.volume = 1.0
        song.patterns[0].rows = [Pattern.emptyRow]
        song.patterns[0].rows[0][0] = 48
        song.patterns.append(Pattern(name: "B", length: 16, trackCount: 1))
        song.arrangement = song.patterns.map { SongSection(patternID: $0.id) }
        studio.open(song)
        studio.engine.core.start()
        _ = render(seconds: 0.5)

        studio.clearPattern(at: 1)
        XCTAssertGreaterThan(RenderHarness.rms(render(seconds: 0.2)[4410...]), 0.01,
                             "clearing another pattern cut a note this one was playing")

        studio.clearPattern(at: 0)
        XCTAssertLessThan(RenderHarness.rms(render(seconds: 0.2)[4410...]), 0.01,
                          "clearing the pattern the note came from left it ringing")
    }

    /// Undo reaches the grid the same way a tap does, so it needs the same
    /// reconcile — undoing the edit that placed a held note must silence it.
    func testUndoDoesNotLeaveAClearedNoteRinging() {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .triangle)]
        song.tracks[0].instrument.sustain = true
        song.tracks[0].instrument.volume = 1.0
        song.patterns[0].rows = [Pattern.emptyRow]
        studio.open(song)
        studio.engine.core.start()

        studio.checkpoint()
        studio.setNote(track: 0, step: 0, note: 48)
        XCTAssertGreaterThan(RenderHarness.rms(render(seconds: 0.5)[4410...]), 0.01)

        studio.undo()

        XCTAssertLessThan(RenderHarness.rms(render(seconds: 0.2)[4410...]), 0.01,
                          "undoing the note that started it left the voice ringing")
    }

    /// Track indices shift when one is removed, so a per-track release would be
    /// aimed at the wrong voice. Everything gets cut instead.
    func testRemovingATrackCutsItsHeldNote() {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .pulse1), Track(kind: .triangle)]
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        song.tracks[1].instrument.sustain = true
        song.tracks[1].instrument.volume = 1.0
        song.patterns[0].rows[1][0] = 48
        studio.open(song)
        studio.engine.core.start()
        _ = render(seconds: 0.5)

        studio.removeTrack(at: 1)

        XCTAssertLessThan(RenderHarness.rms(render(seconds: 0.2)[4410...]), 0.01,
                          "a deleted track's held note carried on sounding")
    }

    /// Previewing a muted track would be silent either way, so the early
    /// return looks cosmetic — it isn't. `audition` marks the voice it takes as
    /// having no originating cell, which is the record `reconcileRingingVoices`
    /// needs to find and release a held note. Without the guard, a header tap
    /// on a muted track is a silent no-op that strands the next held note.
    func testPreviewingAMutedTrackDoesNotStealItsRingingVoice() {
        openHeldNote()
        _ = render(seconds: 0.3)
        let source = studio.engine.core.ringingSource(track: 0)
        XCTAssertNotNil(source, "precondition: a pattern note should be ringing")

        studio.song.tracks[0].muted = true
        studio.pushInstrument(0)
        studio.previewTrack(0)

        XCTAssertEqual(studio.engine.core.ringingSource(track: 0)?.step, source?.step,
                       "the preview took over the voice and lost its originating cell")

        // And the record still works: erasing that cell must cut the note.
        studio.song.tracks[0].muted = false
        studio.pushInstrument(0)
        studio.setNote(track: 0, step: 0, note: Chip.emptyNote)
        XCTAssertLessThan(RenderHarness.rms(render(seconds: 0.2)[4410...]), 0.01,
                          "the held note outlived the cell that started it")
    }

    /// Long-pressing a cell plays *that cell's* note on *that cell's* track —
    /// the two things easiest to get wrong, since the obvious implementation
    /// reaches for `selectedNote` and `selectedTrack` instead.
    ///
    /// Track 0 is muted and the armed note is a different pitch, so either
    /// mistake is audible: routing to the selected track gives silence, and
    /// reading the selected note gives the wrong frequency.
    func testPreviewingACellPlaysThatCellsNoteOnThatCellsTrack() {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .triangle), Track(kind: .triangle)]
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        for track in 0...1 {
            song.tracks[track].instrument.sustain = true
            song.tracks[track].instrument.volume = 1.0
        }
        song.tracks[0].muted = true
        let cellNote: Int8 = 69                  // A4, 440 Hz
        song.patterns[0].rows[1][4] = cellNote
        studio.open(song)
        studio.selectedTrack = 0
        studio.selectedNote = 48

        studio.previewCell(track: 1, step: 4)
        let rendered = render(seconds: 0.4)

        let window = rendered[4410..<(4410 + 8820)]
        XCTAssertGreaterThan(RenderHarness.rms(window), 0.01,
                             "the preview should have sounded on track 1, which isn't muted")
        let dominant = RenderHarness.dominantFrequency(
            window, candidates: RenderHarness.semitoneLadder(around: cellNote))
        XCTAssertEqual(dominant ?? 0, NoteName.frequency(cellNote), accuracy: 0.001,
                       "the preview played a pitch the cell doesn't hold")
    }
}
