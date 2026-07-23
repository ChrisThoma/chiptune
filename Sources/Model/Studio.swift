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
    /// Index into `song.tracks`, not a `ChannelKind`.
    var selectedTrack: Int = 0
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

    /// Kind of the track the keyboard is writing to.
    var selectedKind: ChannelKind {
        song.tracks[safe: selectedTrack]?.kind ?? .pulse1
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

    func note(track: Int, step: Int) -> Int8 {
        guard track < song.tracks.count, step < song.tracks[track].notes.count else { return Chip.emptyNote }
        return song.tracks[track].notes[step]
    }

    /// Writes a note into the grid and mirrors it into the live pattern so an
    /// edit is heard on the very next pass without restarting playback.
    func setNote(track: Int, step: Int, note: Int8) {
        guard track < song.tracks.count, step < Chip.maxSteps else { return }
        song.tracks[track].notes[step] = note
        engine.core.setNote(track: track, step: step, note: note)
    }

    /// Tap behaviour: an empty cell takes the selected note, a filled one clears.
    func toggleCell(track: Int, step: Int) {
        let existing = note(track: track, step: step)
        if existing == Chip.emptyNote {
            setNote(track: track, step: step, note: selectedNote)
            audition(selectedNote, on: track)
        } else {
            setNote(track: track, step: step, note: Chip.emptyNote)
        }
    }

    /// Previews a note on a track — the selected one unless told otherwise.
    func audition(_ note: Int8, on track: Int? = nil) {
        engine.startIfNeeded()
        engine.core.audition(track: track ?? selectedTrack, note: note)
    }

    func clearTrack(_ track: Int) {
        guard track < song.tracks.count else { return }
        for step in 0..<Chip.maxSteps {
            setNote(track: track, step: step, note: Chip.emptyNote)
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

    func pushInstrument(_ index: Int) {
        guard index < song.tracks.count else { return }
        let track = song.tracks[index]
        engine.core.setInstrument(track.instrument, kind: track.kind, track: index, muted: track.muted)
    }

    // MARK: Tracks

    /// Appends a track of `kind` and selects it. A song can hold several of the
    /// same kind — three pulses, two triangles — up to `Chip.maxTracks`.
    func addTrack(kind: ChannelKind) {
        guard song.canAddTrack else { return }
        song.tracks.append(Track(kind: kind))
        pushAll()
        selectedTrack = song.tracks.count - 1
    }

    /// Copies a track's sound *and* its notes, which is the quick way to build
    /// an octave double or a delayed echo line.
    func duplicateTrack(at index: Int) {
        guard song.canAddTrack, index < song.tracks.count else { return }
        var copy = song.tracks[index]
        copy.id = UUID()
        song.tracks.insert(copy, at: index + 1)
        pushAll()
        selectedTrack = index + 1
    }

    func removeTrack(at index: Int) {
        guard song.tracks.count > 1, index < song.tracks.count else { return }
        song.tracks.remove(at: index)
        pushAll()
        selectedTrack = min(selectedTrack, song.tracks.count - 1)
    }

    /// Switches a track's waveform, keeping its notes. Volume/decay/duty come
    /// from the new kind's defaults, since a bass triangle's envelope makes no
    /// sense on noise.
    func setKind(_ kind: ChannelKind, for index: Int) {
        guard index < song.tracks.count, song.tracks[index].kind != kind else { return }
        song.tracks[index].kind = kind
        song.tracks[index].instrument = .default(for: kind)
        pushInstrument(index)
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
