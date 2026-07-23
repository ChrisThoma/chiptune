import SwiftUI
import Observation

/// App-wide state: the song being edited, the audio engine, and the editing
/// cursor. Every mutation pushes the relevant slice down to the DSP core.
@Observable
final class Studio {
    var song: Song {
        didSet { if song.id != oldValue.id { pushAll() } }
    }

    /// Note the keyboard will write into the grid.
    var selectedNote: Int8 = 60
    var selectedChannel: Int = 0
    var isPlaying: Bool = false
    /// Mirrors the sequencer position for the playhead highlight.
    var playhead: Int = 0
    var exportURL: URL?

    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private var timer: Timer?

    init() {
        song = Song(name: "Untitled")
        seedDemo()
        pushAll()
    }

    // MARK: Transport

    func togglePlay() {
        isPlaying ? stop() : play()
    }

    func play() {
        engine.startIfNeeded()
        pushAll()
        engine.core.start()
        isPlaying = true
        // 40 Hz is enough for the playhead to look smooth without burning CPU.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.playhead = Int(self.engine.core.currentStep)
        }
    }

    func stop() {
        engine.core.stop()
        isPlaying = false
        timer?.invalidate()
        timer = nil
        playhead = 0
    }

    // MARK: Editing

    func note(channel: Int, step: Int) -> Int8 {
        guard channel < song.tracks.count, step < song.tracks[channel].notes.count else { return Chip.emptyNote }
        return song.tracks[channel].notes[step]
    }

    /// Writes a note into the grid and mirrors it into the live pattern so an
    /// edit is heard on the very next pass without restarting playback.
    func setNote(channel: Int, step: Int, note: Int8) {
        guard channel < song.tracks.count, step < Chip.maxSteps else { return }
        song.tracks[channel].notes[step] = note
        engine.core.setNote(channel: channel, step: step, note: note)
    }

    /// Tap behaviour: an empty cell takes the selected note, a filled one clears.
    func toggleCell(channel: Int, step: Int) {
        let existing = note(channel: channel, step: step)
        if existing == Chip.emptyNote {
            setNote(channel: channel, step: step, note: selectedNote)
            audition(selectedNote)
        } else {
            setNote(channel: channel, step: step, note: Chip.emptyNote)
        }
    }

    func audition(_ note: Int8) {
        engine.startIfNeeded()
        engine.core.audition(channel: selectedChannel, note: note)
    }

    func clearTrack(_ channel: Int) {
        guard channel < song.tracks.count else { return }
        for step in 0..<Chip.maxSteps {
            setNote(channel: channel, step: step, note: Chip.emptyNote)
        }
    }

    func clearAll() {
        for c in 0..<song.tracks.count { clearTrack(c) }
    }

    // MARK: Parameter sync

    func pushAll() {
        var s = song
        s.normalize()
        song = s
        engine.core.load(song: s)
        engine.core.masterVolume = 0.9
    }

    func pushTransport() {
        engine.core.tempo = song.tempo
        engine.core.length = Int32(song.length)
    }

    func pushInstrument(_ channel: Int) {
        guard channel < song.tracks.count else { return }
        let track = song.tracks[channel]
        engine.core.setInstrument(track.instrument, kind: track.kind, channel: channel, muted: track.muted)
    }

    // MARK: Song management

    func save() { SongStore.shared.save(song) }

    func newSong() {
        stop()
        song = Song(name: "Untitled")
        pushAll()
    }

    func open(_ other: Song) {
        stop()
        var s = other
        s.normalize()
        song = s
        pushAll()
    }

    func export() {
        exportURL = WavExport.render(song: song)
    }

    /// A short riff so the app makes noise the moment it opens.
    private func seedDemo() {
        song.name = "First Loop"
        song.tempo = 132
        song.length = 16
        let lead: [Int8] = [72, -1, 76, -1, 79, -1, 76, -1, 74, -1, 77, -1, 81, -1, 79, -1]
        let harmony: [Int8] = [-1, 64, -1, 67, -1, 64, -1, 67, -1, 65, -1, 69, -1, 65, -1, 62]
        let bass: [Int8] = [48, -1, -1, -1, 48, -1, -1, -1, 53, -1, -1, -1, 43, -1, -1, -1]
        let drums: [Int8] = [60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, 60, -1]
        for (i, notes) in [lead, harmony, bass, drums].enumerated() {
            for (step, n) in notes.enumerated() { song.tracks[i].notes[step] = n }
        }
    }
}
