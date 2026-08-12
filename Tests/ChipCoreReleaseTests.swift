import XCTest
@testable import Chiptune

/// The main thread's way of cutting a voice it can't reach any other way.
///
/// A sustaining note is only ended by a note-off cell, a new note, or STOP. An
/// edit that removes the note which started it has none of those to offer, so
/// the core needs an explicit release — and it has to survive being issued
/// while the audio thread is mid-buffer, because `voiceSample` rewrites the
/// whole voice struct every sample and would drop a flag set underneath it.
final class ChipCoreReleaseTests: XCTestCase {

    private let sampleRate = RenderHarness.sampleRate

    /// A held triangle sounding on track 0, already past its attack.
    private func heldCore() -> ChipCore {
        var song = TestSongs.singleNote(kind: .triangle, note: 48, sustain: true)
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.start()
        return core
    }

    private func level(_ samples: [Float]) -> Double {
        RenderHarness.rms(samples[(samples.count - 4410)...])
    }

    func testReleaseCutsASustainingVoice() {
        let core = heldCore()
        XCTAssertGreaterThan(level(RenderHarness.renderMono(core, frames: 22050)), 0.01)

        core.release(track: 0)

        XCTAssertLessThan(level(RenderHarness.renderMono(core, frames: 8820)), 0.01,
                          "release left the voice sounding")
    }

    func testReleaseAllCutsEverySoundingVoice() {
        var song = TestSongs.empty(tempo: 120)
        song.tracks = [Track(kind: .triangle), Track(kind: .pulse1)]
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        for track in 0..<2 {
            song.tracks[track].instrument.decay = 4.0
            song.tracks[track].instrument.volume = 1.0
            song.patterns[0].rows[track][0] = Int8(48 + track * 12)
        }
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.start()
        XCTAssertGreaterThan(level(RenderHarness.renderMono(core, frames: 22050)), 0.01)

        core.releaseAll()

        XCTAssertLessThan(level(RenderHarness.renderMono(core, frames: 8820)), 0.01)
    }

    /// Nothing to cut, and nowhere to write: neither should disturb the render
    /// loop or trip a bounds check.
    func testReleaseOnAnIdleOrOutOfRangeTrackIsIgnored() {
        let core = heldCore()
        _ = RenderHarness.renderMono(core, frames: 22050)

        core.release(track: 3)              // in range, never triggered
        core.release(track: -1)
        core.release(track: Chip.maxTracks)
        core.release(track: 999)

        XCTAssertGreaterThan(level(RenderHarness.renderMono(core, frames: 8820)), 0.01,
                             "releasing some other track cut the one that was sounding")
    }

    /// The test the token design exists for. A release arriving between two
    /// render calls is easy; one arriving while the audio thread is partway
    /// through a buffer is where a naive write into the voice gets clobbered.
    /// Rendering in small chunks with a release in the middle is as close as an
    /// offline test gets to that race, and it must not drop the request.
    func testAReleaseIssuedMidBufferIsNotLost() {
        for chunk in [1, 7, 64, 1024] {
            let core = heldCore()
            _ = RenderHarness.renderMono(core, frames: 22050, chunk: chunk)

            core.release(track: 0)

            let after = RenderHarness.renderMono(core, frames: 8820, chunk: chunk)
            XCTAssertLessThan(level(after), 0.01,
                              "a release issued at a \(chunk)-frame chunk size was lost")
        }
    }

    /// Nothing syncs the release token when the transport restarts, so this is
    /// the check that it doesn't need to: a release issued while stopped must
    /// not carry over and cut the first note of the next run.
    func testAReleaseIssuedWhileStoppedDoesNotCutTheNextNote() {
        var song = TestSongs.singleNote(kind: .triangle, note: 48, sustain: true)
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)

        core.release(track: 0)          // nothing is sounding yet
        core.start()

        XCTAssertGreaterThan(level(RenderHarness.renderMono(core, frames: 22050)), 0.01,
                             "a stale release cut the first note after START")
    }

    // MARK: Attributing a ringing voice to the cell that started it

    func testRingingSourceReportsTheTriggeringCell() {
        let core = heldCore()
        _ = RenderHarness.renderMono(core, frames: 22050)

        let source = core.ringingSource(track: 0)

        XCTAssertEqual(source?.pattern, 0)
        XCTAssertEqual(source?.step, 0)
    }

    func testRingingSourceIsNilForASilentTrack() {
        let core = heldCore()
        _ = RenderHarness.renderMono(core, frames: 22050)

        XCTAssertNil(core.ringingSource(track: 1))
        XCTAssertNil(core.ringingSource(track: -1))
        XCTAssertNil(core.ringingSource(track: Chip.maxTracks))
    }

    /// A keyboard preview belongs to no cell. Reporting one would make the
    /// reconcile step cut previews whenever the grid happened to be empty there.
    func testRingingSourceIsNilForAKeyboardPreview() {
        var song = TestSongs.singleNote(kind: .triangle, note: 48, sustain: true)
        song.patterns[0].rows[0][0] = Chip.emptyNote      // nothing in the grid
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.audition(track: 0, note: 60)
        _ = RenderHarness.renderMono(core, frames: 4410)

        XCTAssertNil(core.ringingSource(track: 0), "a preview was attributed to a pattern cell")
    }

    /// `audition` only grants a preview its own lifetime when the instrument is
    /// already sustaining — a decaying one was going to end by itself. Turning
    /// Hold on while that preview is still ringing used to remove the only
    /// thing that would ever stop it.
    func testTurningHoldOnDuringAPreviewStillEndsTheNote() {
        var song = TestSongs.singleNote(kind: .triangle, note: 48, sustain: false)
        song.patterns[0].rows[0][0] = Chip.emptyNote
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.audition(track: 0, note: 60)
        _ = RenderHarness.renderMono(core, frames: 4410)

        var held = song.tracks[0].instrument
        held.decay = 4.0
        core.setInstrument(held, kind: .triangle, track: 0, muted: false)

        // Longer than `previewSeconds` plus the release tail.
        let after = RenderHarness.renderMono(core, frames: Int(sampleRate * 1.5))
        XCTAssertLessThan(level(after), 0.01,
                          "turning Hold on mid-preview left the note ringing forever")
    }
}
