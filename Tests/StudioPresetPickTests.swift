import XCTest
@testable import Chiptune

/// Tapping a preset chip in the sound panel: it applies the sound and plays a
/// note of it, so you hear what you picked without leaving the panel.
///
/// The audio half is measured the way `StudioSustainTests` does it, by
/// rendering the studio's own core offline after the pick.
@MainActor
final class StudioPresetPickTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    private let sampleRate = RenderHarness.sampleRate

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.undoCoalescingWindow = 0
    }

    override func tearDown() {
        studio.engine.stopEngine()
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    /// Two tracks, no notes, so anything the render hears came from the pick.
    private func openSilentSong(kinds: [ChannelKind] = [.pulse1, .triangle]) {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = kinds.map { Track(kind: $0) }
        song.patterns[0].rows = kinds.map { _ in Pattern.emptyRow }
        studio.open(song)
    }

    private func preset(_ name: String, _ kind: ChannelKind) throws -> InstrumentPreset {
        try XCTUnwrap(InstrumentPreset.presets(for: kind).first { $0.name == name },
                      "no \(kind.fullName) preset named \(name)")
    }

    /// A preview starts the real audio output, whose render thread then pulls
    /// frames from the same core. The voice is already set by then; stopping
    /// the output leaves the test as the only listener.
    private func renderAfterPreview(seconds: Double) -> [Float] {
        studio.engine.stopEngine()
        return RenderHarness.renderMono(studio.engine.core, frames: Int(sampleRate * seconds))
    }

    // MARK: The song

    func testPickingAPresetAppliesItsSound() throws {
        openSilentSong()
        let blip = try preset("Blip", .pulse1)

        studio.pickPreset(blip, for: 0)

        XCTAssertEqual(studio.song.tracks[0].instrument, blip.instrument)
        XCTAssertEqual(InstrumentPreset.matching(studio.song.tracks[0].instrument, kind: .pulse1)?.name,
                       "Blip")
    }

    func testPickingAPresetIsOneUndoStep() throws {
        openSilentSong()
        let before = studio.song.tracks[0].instrument
        XCTAssertFalse(studio.canUndo, "precondition: a freshly opened song has no history")

        studio.pickPreset(try preset("Chord", .pulse1), for: 0)
        XCTAssertTrue(studio.canUndo)

        studio.undo()
        XCTAssertEqual(studio.song.tracks[0].instrument, before)
        XCTAssertFalse(studio.canUndo, "the pick took more than one undo step")
    }

    /// Re-tapping the selected chip is how you hear it again. That is not an
    /// edit: no Undo step, and Redo survives.
    func testRePickingTheCurrentPresetChangesNothingInTheSong() throws {
        openSilentSong()
        let lead = try preset("Lead", .pulse1)
        XCTAssertEqual(studio.song.tracks[0].instrument, lead.instrument,
                       "precondition: a new pulse 1 track starts on Lead")
        // Arm Redo with one real edit, undone.
        studio.pickPreset(try preset("Blip", .pulse1), for: 0)
        studio.undo()
        XCTAssertTrue(studio.canRedo)
        let song = studio.song

        studio.pickPreset(lead, for: 0)

        XCTAssertEqual(studio.song, song)
        XCTAssertFalse(studio.canUndo, "re-picking the current preset added an undo step")
        XCTAssertTrue(studio.canRedo, "re-picking the current preset wiped Redo")
    }

    func testPickingOnAMissingTrackDoesNothing() throws {
        openSilentSong()
        let song = studio.song

        let played = studio.pickPreset(try preset("Blip", .pulse1), for: 7)

        XCTAssertFalse(played)
        XCTAssertEqual(studio.song, song)
        XCTAssertFalse(studio.canUndo)
    }

    // MARK: The preview

    func testPickingAPresetPlaysIt() throws {
        openSilentSong()

        let played = studio.pickPreset(try preset("Pluck", .pulse1), for: 0)

        XCTAssertTrue(played)
        XCTAssertGreaterThan(RenderHarness.rms(renderAfterPreview(seconds: 0.1)), 0.01,
                             "picking a preset made no sound")
    }

    /// The tap on the chip that's already lit is the "play it again" gesture,
    /// so the no-op on the song must not swallow the preview.
    func testRePickingTheCurrentPresetStillPlaysIt() throws {
        openSilentSong()

        let played = studio.pickPreset(try preset("Lead", .pulse1), for: 0)

        XCTAssertTrue(played)
        XCTAssertGreaterThan(RenderHarness.rms(renderAfterPreview(seconds: 0.1)), 0.01,
                             "re-tapping the selected preset was silent")
    }

    /// The preview is on the track that was picked for, not the selected one.
    func testThePreviewPlaysOnThePickedTrack() throws {
        openSilentSong()
        studio.selectedTrack = 0
        studio.song.tracks[0].muted = true
        studio.pushInstrument(0)

        let played = studio.pickPreset(try preset("Sub", .triangle), for: 1)

        XCTAssertTrue(played)
        XCTAssertGreaterThan(RenderHarness.rms(renderAfterPreview(seconds: 0.1)), 0.01,
                             "the preview went to the selected (muted) track instead")
    }

    /// A muted track still takes the sound, but plays nothing — and, like a
    /// header tap, doesn't take over the voice (see `previewNote(forTrack:)`).
    func testPickingOnAMutedTrackAppliesTheSoundWithoutPlayingIt() throws {
        openSilentSong()
        studio.toggleMute(track: 0)
        let blip = try preset("Blip", .pulse1)

        let played = studio.pickPreset(blip, for: 0)

        XCTAssertFalse(played)
        XCTAssertEqual(studio.song.tracks[0].instrument, blip.instrument)
        XCTAssertLessThan(RenderHarness.rms(renderAfterPreview(seconds: 0.1)), 0.001)
    }

    /// "Pad (holds)" and "Drone (holds)" have no decay to end them and no
    /// pattern step comes along to cut a preview, so it has to stop by itself.
    func testPreviewingAHeldPresetStopsByItself() throws {
        for (name, kind) in [("Pad (holds)", ChannelKind.pulse1), ("Drone (holds)", .triangle)] {
            openSilentSong(kinds: [kind])
            let held = try preset(name, kind)
            XCTAssertTrue(held.instrument.sustain, "precondition: \(name) holds")

            XCTAssertTrue(studio.pickPreset(held, for: 0))
            let samples = renderAfterPreview(seconds: 2.0)

            XCTAssertGreaterThan(RenderHarness.rms(samples[0..<4410]), 0.01, "\(name) preview was silent")
            XCTAssertLessThan(RenderHarness.rms(samples[(samples.count - 4410)...]), 0.001,
                              "\(name) preview was still ringing 2 s later")
        }
    }
}
