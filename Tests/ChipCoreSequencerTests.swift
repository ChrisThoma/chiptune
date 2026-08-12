import XCTest
@testable import Chiptune

/// The sequencer's contract: steps land on the sample the tempo says they
/// should, PATT loops one pattern, SONG walks the chain with its repeats and
/// wraps, and nothing the UI can do to a pattern mid-playback sends the
/// playhead somewhere that doesn't exist.
final class ChipCoreSequencerTests: XCTestCase {

    private let sampleRate = RenderHarness.sampleRate

    /// The core's own rounding, restated here so the tests assert against the
    /// tempo rather than against the implementation.
    private func samplesPerStep(tempo: Double) -> Int {
        Int((sampleRate * 60.0 / (tempo * 4.0)).rounded())
    }

    private func makeCore(_ song: Song, songMode: Bool = false) -> ChipCore {
        var song = song
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.setSongMode(songMode)
        core.start()
        return core
    }

    // MARK: Step timing

    /// Notes must fire on the step boundary the tempo defines, not merely "in
    /// roughly the right order". This is measured off the audio itself: a note
    /// on every step, decaying fast enough to leave a silent gap, so each
    /// trigger is a detectable onset.
    func testStepsTriggerOnTheSamplesPerStepBoundary() {
        let tempo = 120.0
        var song = TestSongs.empty(tempo: tempo)
        song.tracks = [Track(kind: .pulse1)]
        song.tracks[0].instrument.decay = 0.05
        song.tracks[0].instrument.volume = 1.0
        song.patterns[0].rows = [Pattern.emptyRow]
        for step in 0..<8 { song.patterns[0].rows[0][step] = 60 }

        let sps = samplesPerStep(tempo: tempo)
        let core = makeCore(song)
        let samples = RenderHarness.renderMono(core, frames: sps * 6)

        let onsets = RenderHarness.onsets(samples, refractory: sps / 2)
        XCTAssertEqual(onsets.count, 6, "one onset per step: \(onsets)")

        // The detector works on a 128-sample envelope window, so it can only
        // ever place an onset to within one window of the true boundary.
        for (index, onset) in onsets.enumerated() {
            XCTAssertEqual(Double(onset), Double(index * sps), accuracy: 256,
                           "step \(index) fired at \(onset), expected \(index * sps)")
        }
    }

    /// The tempo→sample-count conversion rounds, and a tempo whose step length
    /// isn't a whole number of samples is the normal case, not the exception.
    func testStepLengthTracksTempoIncludingRounding() {
        for tempo in [120.0, 132.0, 175.0, 300.0] {
            let sps = samplesPerStep(tempo: tempo)
            var song = TestSongs.empty(tempo: tempo)
            song.tracks = [Track(kind: .pulse1)]
            song.patterns[0].rows = [Pattern.emptyRow]

            let core = makeCore(song)
            // One step short of the boundary the step must not have advanced;
            // one sample past it, it must have.
            _ = RenderHarness.renderMono(core, frames: sps - 1)
            XCTAssertEqual(core.currentStep, 0, "at \(tempo) BPM the step advanced early")
            _ = RenderHarness.renderMono(core, frames: 2)
            XCTAssertEqual(core.currentStep, 1, "at \(tempo) BPM the step didn't advance on time")
        }
    }

    // MARK: PATT mode

    func testPatternModeLoopsTheFocusedPatternForever() {
        let song = TestSongs.twoPatterns(lengths: (4, 16))
        let core = makeCore(song, songMode: false)
        core.focus(pattern: 1)

        let sps = samplesPerStep(tempo: 120)
        // Well past pattern B's own length, so a chain walk would have moved on.
        for _ in 0..<40 {
            _ = RenderHarness.renderMono(core, frames: sps)
            XCTAssertEqual(core.currentPattern, 1, "PATT mode must not leave the focused pattern")
        }
    }

    func testPatternLoopsBackToStepZeroAtItsOwnLength() {
        var song = TestSongs.empty(tempo: 120, length: 4)
        song.tracks = [Track(kind: .pulse1)]
        song.patterns[0].rows = [Pattern.emptyRow]

        let sps = samplesPerStep(tempo: 120)
        let core = makeCore(song)

        var seen: [Int32] = []
        for _ in 0..<9 {
            seen.append(core.currentStep)
            _ = RenderHarness.renderMono(core, frames: sps)
        }
        XCTAssertEqual(seen, [0, 1, 2, 3, 0, 1, 2, 3, 0])
    }

    /// Selecting a different pattern while PATT is playing switches to it —
    /// the editing cursor and the thing you hear are meant to be the same.
    func testFocusChangeSwitchesPatternInPattMode() {
        let song = TestSongs.twoPatterns(lengths: (16, 16))
        let sps = samplesPerStep(tempo: 120)
        let core = makeCore(song, songMode: false)

        _ = RenderHarness.renderMono(core, frames: sps * 3)
        XCTAssertEqual(core.currentPattern, 0)

        core.focus(pattern: 1)
        XCTAssertEqual(core.currentPattern, 1)

        // And it stays there across the pattern boundary rather than snapping
        // back to whatever was playing before.
        _ = RenderHarness.renderMono(core, frames: sps * 20)
        XCTAssertEqual(core.currentPattern, 1)
    }

    // MARK: SONG mode

    func testSongModeWalksTheChainWithRepeatsAndWraps() {
        // A twice, then B once: chain [0, 0, 1], 16 + 16 + 8 = 40 steps a pass.
        let song = TestSongs.twoPatterns(lengths: (16, 8), repeats: (2, 1))
        XCTAssertEqual(song.chain, [0, 0, 1], "the test's premise: the flattened chain")

        let sps = samplesPerStep(tempo: 120)
        let core = makeCore(song, songMode: true)

        var seen: [Int32] = []
        // One and a half passes, so the wrap back to the top is covered.
        for _ in 0..<60 {
            seen.append(core.currentPattern)
            _ = RenderHarness.renderMono(core, frames: sps)
        }

        let expected: [Int32] = Array(repeating: 0, count: 32)
            + Array(repeating: 1, count: 8)
            + Array(repeating: 0, count: 20)
        XCTAssertEqual(seen, expected)
    }

    func testSongModeStartsAtTheTopOfTheChain() {
        let song = TestSongs.twoPatterns(lengths: (16, 16))
        let core = makeCore(song, songMode: false)
        core.focus(pattern: 1)
        XCTAssertEqual(core.currentPattern, 1)

        core.setSongMode(true)
        XCTAssertEqual(core.currentPattern, 0, "SONG must begin at the start of the arrangement")
    }

    /// `start()` rewinds the playhead. It no longer does so on the calling
    /// thread — the reset is handed to the audio thread as a token, because
    /// `render` mutates these fields in place and a main-thread write inside
    /// one of those accesses is a Swift exclusivity violation. That is an
    /// implementation detail the caller must not be able to feel: the first
    /// buffer after `start()` has to play from the top either way.
    func testStartRewindsThePlayheadOnTheNextBuffer() {
        let song = TestSongs.twoPatterns(lengths: (16, 16))
        let sps = samplesPerStep(tempo: 120)
        let core = makeCore(song, songMode: false)

        _ = RenderHarness.renderMono(core, frames: sps * 5)
        XCTAssertEqual(core.currentStep, 5, "precondition: the playhead moved")

        core.start()
        _ = RenderHarness.renderMono(core, frames: 1)
        XCTAssertEqual(core.currentStep, 0, "start() must rewind to the top")
        XCTAssertEqual(core.currentPattern, 0)
    }

    // MARK: Hostile edits mid-playback

    /// The pattern being edited can shrink under the playhead — STEPS is a
    /// stepper the user can hit at any time, including while it's playing.
    func testPatternShrinkingUnderThePlayheadResetsTheStep() {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .pulse1)]
        song.patterns[0].rows = [Pattern.emptyRow]

        let sps = samplesPerStep(tempo: 120)
        let core = makeCore(song)

        _ = RenderHarness.renderMono(core, frames: sps * 10)
        XCTAssertEqual(core.currentStep, 10)

        core.setLength(pattern: 0, length: 4)
        _ = RenderHarness.renderMono(core, frames: 64)
        XCTAssertLessThan(core.currentStep, 4, "the playhead must fold back inside the shorter pattern")
    }

    func testSetChainClampsSlotsAndCount() {
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: TestSongs.empty())

        core.setChain([])
        XCTAssertEqual(core.chainCount, 1, "an empty chain still has to play something")

        core.setChain(Array(repeating: 0, count: Chip.maxChain * 4))
        XCTAssertEqual(core.chainCount, Int32(Chip.maxChain))

        // Out-of-range slots are clamped rather than indexing off the end of
        // the pattern table on the audio thread.
        core.setChain([-5, 999, 1])
        XCTAssertEqual(core.chainCount, 3)
        core.setSongMode(true)
        core.start()
        let samples = RenderHarness.renderMono(core, frames: Int(sampleRate))
        XCTAssertFalse(samples.contains { !$0.isFinite })
        XCTAssertLessThan(core.currentPattern, core.patternCount)
    }

    /// Deleting patterns leaves the core focused somewhere that no longer
    /// exists unless `load` pulls it back.
    func testLoadPullsFocusInsideTheNewPatternCount() {
        var song = TestSongs.twoPatterns()
        let core = makeCore(song, songMode: false)
        core.focus(pattern: 1)
        XCTAssertEqual(core.focusPattern, 1)

        song.patterns.removeLast()
        song.normalize()
        core.load(song: song)

        XCTAssertLessThan(core.focusPattern, core.patternCount)
        XCTAssertLessThan(core.currentPattern, core.patternCount)
    }
}
