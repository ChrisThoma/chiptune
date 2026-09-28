import XCTest
@testable import Chiptune

/// Reordering tracks. A track is more than its column header: its notes sit in
/// a row of *every* pattern, and the audio core addresses both notes and
/// instrument by track index. A move that shuffled `song.tracks` alone would
/// look right in the header and play every part on someone else's sound.
@MainActor
final class StudioTrackMoveTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    private let sampleRate = RenderHarness.sampleRate

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        // A blank song, so the demo riff's notes don't muddy the rows below.
        studio.open(Song(name: "Blank"))
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    private var trackIDs: [UUID] { studio.song.tracks.map(\.id) }

    // MARK: The model

    func testMovingATrackCarriesItsNotesInEveryPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(track: 0, step: 3, note: 60)
        studio.selectPattern(1)
        studio.setNote(track: 0, step: 7, note: 67)
        let moved = studio.song.tracks[0].id

        studio.moveTrack(from: 0, to: 2)

        XCTAssertEqual(studio.song.tracks[2].id, moved)
        XCTAssertEqual(studio.song.patterns[0].rows[2][3], 60)
        XCTAssertEqual(studio.song.patterns[1].rows[2][7], 67)
        XCTAssertEqual(studio.song.patterns[0].rows[0][3], Chip.emptyNote,
                       "the note stayed behind in the column the track left")
        for pattern in studio.song.patterns {
            XCTAssertEqual(pattern.rows.count, studio.song.tracks.count)
        }
    }

    /// Everything else a track owns rides along on the `Track` value itself.
    func testMovingATrackKeepsItsSoundMuteAndName() {
        studio.song.tracks[3].muted = true
        studio.song.tracks[3].name = "Hats"
        studio.song.tracks[3].instrument.volume = 0.3
        let before = studio.song.tracks[3]

        studio.moveTrack(from: 3, to: 0)

        XCTAssertEqual(studio.song.tracks[0], before)
    }

    func testTheOtherTracksCloseUpInOrder() {
        let ids = trackIDs

        studio.moveTrack(from: 1, to: 3)

        XCTAssertEqual(trackIDs, [ids[0], ids[2], ids[3], ids[1]])
    }

    func testAMoveIsOneUndoStepAndRedoes() {
        studio.setNote(track: 1, step: 0, note: 72)
        let before = studio.song
        let ids = trackIDs

        studio.moveTrack(from: 1, to: 3)
        let after = studio.song

        studio.undo()
        XCTAssertEqual(trackIDs, ids)
        XCTAssertEqual(studio.song.patterns, before.patterns)

        studio.redo()
        XCTAssertEqual(studio.song.tracks, after.tracks)
        XCTAssertEqual(studio.song.patterns, after.patterns)
    }

    // MARK: Selection

    func testTheSelectionFollowsTheMovedTrack() {
        studio.selectedTrack = 1
        let selected = studio.song.tracks[1].id

        studio.moveTrack(from: 1, to: 3)

        XCTAssertEqual(studio.song.tracks[studio.selectedTrack].id, selected)
    }

    /// Moving some other track past the selected one shifts its index, and
    /// the selection has to shift with it or the editor jumps to a neighbor.
    func testTheSelectionStaysOnItsTrackWhenAnotherMovesPastIt() {
        studio.selectedTrack = 2
        let selected = studio.song.tracks[2].id

        studio.moveTrack(from: 0, to: 3)

        XCTAssertEqual(studio.selectedTrack, 1)
        XCTAssertEqual(studio.song.tracks[studio.selectedTrack].id, selected)
    }

    func testUndoingAMovePutsTheSelectionBack() {
        studio.selectedTrack = 0
        studio.moveTrack(from: 0, to: 3)
        XCTAssertEqual(studio.selectedTrack, 3)

        studio.undo()

        XCTAssertEqual(studio.selectedTrack, 0)
    }

    // MARK: Refusals

    /// A drop back where the drag began is not an edit, and must not leave an
    /// undo step that does nothing.
    func testMovingATrackOntoItselfIsNotAnEdit() {
        let ids = trackIDs

        studio.moveTrack(from: 2, to: 2)

        XCTAssertEqual(trackIDs, ids)
        XCTAssertFalse(studio.canUndo)
    }

    func testOutOfRangeMovesAreIgnored() {
        let ids = trackIDs

        studio.moveTrack(from: 0, to: 4)
        studio.moveTrack(from: 0, to: -1)
        studio.moveTrack(from: 9, to: 0)
        studio.moveTrack(from: -1, to: 0)

        XCTAssertEqual(trackIDs, ids)
        XCTAssertFalse(studio.canUndo)
    }

    // MARK: Labels

    /// Unnamed duplicates are lettered by position, left to right. That stays
    /// true after a move: the letters describe the columns as they now stand,
    /// so the leftmost triangle is always "A". A name the user gave is theirs
    /// and travels with the track.
    func testDuplicateLettersFollowTheNewColumnOrder() {
        var song = Song(name: "Letters")
        song.tracks = [Track(kind: .triangle), Track(kind: .pulse1), Track(kind: .triangle)]
        song.tracks[1].name = "Lead"
        song.patterns[0].rows = song.tracks.map { _ in Pattern.emptyRow }
        studio.open(song)
        let wasB = studio.song.tracks[2].id
        XCTAssertEqual(studio.song.label(for: 2), "TRI B")

        studio.moveTrack(from: 2, to: 0)
        studio.moveTrack(from: 2, to: 1)

        XCTAssertEqual(studio.song.tracks[0].id, wasB)
        XCTAssertEqual(studio.song.label(for: 0), "TRI A")
        XCTAssertEqual(studio.song.label(for: 1), "Lead")
        XCTAssertEqual(studio.song.fullLabel(for: 1), "Lead")
        XCTAssertEqual(studio.song.label(for: 2), "TRI B")
        XCTAssertEqual(studio.song.fullLabel(for: 2), "Triangle B")
    }

    // MARK: The audio core

    /// Two held triangles, the first muted. After the move the core must hear
    /// the unmuted one's pitch: if the notes moved but the mute stayed on its
    /// old index (or the reverse), the muted part's pitch is what sounds.
    func testTheCorePlaysEachTrackWithItsOwnSoundAfterAMove() {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .triangle), Track(kind: .triangle)]
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        for track in 0...1 {
            song.tracks[track].instrument.sustain = true
            song.tracks[track].instrument.volume = 1.0
        }
        song.tracks[0].muted = true
        song.patterns[0].rows[0][0] = 69          // A4, muted
        song.patterns[0].rows[1][0] = 60          // C4, audible
        studio.open(song)

        studio.moveTrack(from: 0, to: 1)
        studio.engine.core.start()
        let rendered = RenderHarness.renderMono(studio.engine.core, frames: Int(sampleRate * 0.4))

        let window = rendered[4410..<(4410 + 8820)]
        XCTAssertGreaterThan(RenderHarness.rms(window), 0.01, "the unmuted track fell silent")
        let dominant = RenderHarness.dominantFrequency(
            window, candidates: RenderHarness.semitoneLadder(around: 64))
        XCTAssertEqual(dominant ?? 0, NoteName.frequency(60), accuracy: 0.001,
                       "the muted track's part is what played after the move")
    }

    /// Voices are indexed by track. A note held through the move would keep
    /// ringing on a voice that now belongs to a different track, with that
    /// track's sound, and nothing aimed at the right index could release it.
    func testMovingDuringPlaybackCutsAHeldNote() {
        var song = TestSongs.empty(tempo: 120, length: 16)
        song.tracks = [Track(kind: .triangle), Track(kind: .pulse1)]
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        song.tracks[0].instrument.sustain = true
        song.tracks[0].instrument.volume = 1.0
        song.patterns[0].rows[0][0] = 48
        studio.open(song)
        studio.engine.core.start()
        let before = RenderHarness.renderMono(studio.engine.core, frames: Int(sampleRate * 0.5))
        XCTAssertGreaterThan(RenderHarness.rms(before[(before.count - 4410)...]), 0.01)

        studio.moveTrack(from: 0, to: 1)

        let after = RenderHarness.renderMono(studio.engine.core, frames: Int(sampleRate * 0.2))
        XCTAssertLessThan(RenderHarness.rms(after[4410...]), 0.01,
                          "a held note carried on across the move")
    }
}
