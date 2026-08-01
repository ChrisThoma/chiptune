import SwiftUI
import Observation

/// App-wide state: the song being edited, the audio engine, and the editing
/// cursor. Every mutation pushes the relevant slice down to the DSP core.
@Observable
final class Studio {
    var song: Song {
        didSet {
            if song.id != oldValue.id { pushAll() }
            if song != oldValue { scheduleAutosave() }
        }
    }

    /// Note the keyboard will write into the grid.
    var selectedNote: Int8 = 60
    /// Index into `song.tracks`, not a `ChannelKind`.
    var selectedTrack: Int = 0
    /// Index into `song.patterns` — the pattern the grid is editing.
    var selectedPattern: Int = 0
    /// PATT loops the pattern being edited; SONG follows the arrangement.
    var songMode: Bool = false
    var isPlaying: Bool = false
    /// Mirrors the sequencer position for the playhead highlight.
    var playhead: Int = 0
    /// Pattern the sequencer is actually on, which in SONG mode is not always
    /// the one being edited.
    var playingPattern: Int = 0
    var exportURL: URL?
    /// True while a WAV render is running off the main thread.
    var isExporting = false

    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var autosaveTimer: Timer?

    init() {
        // Reopen whatever was last on screen. Losing an unsaved loop to a
        // relaunch is not a thing this app should ever do, so every edit
        // autosaves and the last song is restored here.
        if let restored = SongStore.shared.loadLast() {
            song = restored
        } else {
            song = Song(name: "Untitled")
            seedDemo()
            SongStore.shared.save(song, makeCurrent: true)
        }
        pushAll()
    }

    /// Kind of the track the keyboard is writing to.
    var selectedKind: ChannelKind {
        song.tracks[safe: selectedTrack]?.kind ?? .pulse1
    }

    var pattern: Pattern {
        song.patterns[safe: selectedPattern] ?? song.patterns[0]
    }

    /// Number of steps shown in the grid.
    var patternLength: Int { pattern.length }

    // MARK: Transport

    func togglePlay() {
        isPlaying ? stop() : play()
    }

    func play() {
        engine.startIfNeeded()
        pushAll()
        engine.core.setSongMode(songMode)
        engine.core.start()
        isPlaying = true
        startPlayheadTimer()
    }

    func stop() {
        engine.core.stop()
        isPlaying = false
        timer?.invalidate()
        timer = nil
        playhead = 0
    }

    /// The playhead used to freeze whenever a scroll was in flight: a timer
    /// scheduled the usual way only fires in the default run loop mode, and
    /// UIKit switches to tracking mode for the duration of a drag. Adding it in
    /// `.common` keeps it running through the scroll.
    private func startPlayheadTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.playhead = Int(self.engine.core.currentStep)
            let pattern = Int(self.engine.core.currentPattern)
            if self.playingPattern != pattern {
                self.playingPattern = pattern
                // Following the arrangement means the grid should follow too,
                // otherwise you're watching a playhead run over the wrong notes.
                if self.songMode, pattern < self.song.patterns.count {
                    self.selectedPattern = pattern
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setSongMode(_ on: Bool) {
        songMode = on
        engine.core.setSongMode(on)
        if !on { playingPattern = selectedPattern }
    }

    func setTempo(_ bpm: Double) {
        song.tempo = min(max(bpm, 40), 300)
        pushTransport()
    }

    // MARK: Editing

    func note(track: Int, step: Int) -> Int8 {
        guard let row = pattern.rows[safe: track], let note = row[safe: step] else {
            return Chip.emptyNote
        }
        return note
    }

    /// Writes a note into the grid and mirrors it into the live pattern so an
    /// edit is heard on the very next pass without restarting playback.
    func setNote(track: Int, step: Int, note: Int8) {
        guard selectedPattern < song.patterns.count,
              track < song.tracks.count, step < Chip.maxSteps else { return }
        song.patterns[selectedPattern].rows[track][step] = note
        engine.core.setNote(pattern: selectedPattern, track: track, step: step, note: note)
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

    /// Clears one track in the pattern being edited.
    func clearTrack(_ track: Int) {
        guard track < song.tracks.count else { return }
        for step in 0..<Chip.maxSteps {
            setNote(track: track, step: step, note: Chip.emptyNote)
        }
    }

    /// Clears every track in the pattern being edited. Other patterns are left
    /// alone — the arrangement is the song, so this is not "clear everything".
    func clearPattern() {
        for c in 0..<song.tracks.count { clearTrack(c) }
    }

    // MARK: Parameter sync

    func pushAll() {
        var s = song
        s.normalize()
        song = s
        selectedPattern = min(selectedPattern, s.patterns.count - 1)
        selectedTrack = min(selectedTrack, s.tracks.count - 1)
        engine.core.load(song: s)
        engine.core.focus(pattern: selectedPattern)
        engine.core.masterVolume = 0.9
    }

    func pushTransport() {
        engine.core.tempo = song.tempo
        for (i, p) in song.patterns.enumerated() {
            engine.core.setLength(pattern: i, length: p.length)
        }
    }

    func pushArrangement() {
        engine.core.setChain(song.chain)
    }

    func pushInstrument(_ index: Int) {
        guard index < song.tracks.count else { return }
        let track = song.tracks[index]
        engine.core.setInstrument(track.instrument, kind: track.kind, track: index, muted: track.muted)
    }

    // MARK: Patterns

    func selectPattern(_ index: Int) {
        guard index >= 0, index < song.patterns.count else { return }
        selectedPattern = index
        engine.core.focus(pattern: index)
        if !songMode { playingPattern = index }
    }

    func setPatternLength(_ length: Int) {
        guard selectedPattern < song.patterns.count else { return }
        song.patterns[selectedPattern].length = min(max(length, 4), Chip.maxSteps)
        engine.core.setLength(pattern: selectedPattern, length: song.patterns[selectedPattern].length)
    }

    /// Adds an empty pattern, appends it to the arrangement, and starts editing it.
    @discardableResult
    func addPattern() -> Int? {
        guard song.canAddPattern else { return nil }
        let new = Pattern(name: song.nextPatternName(),
                          length: pattern.length,
                          trackCount: song.tracks.count)
        song.patterns.append(new)
        song.arrangement.append(SongSection(patternID: new.id))
        pushAll()
        pushArrangement()
        selectPattern(song.patterns.count - 1)
        return song.patterns.count - 1
    }

    /// Copies a pattern's notes into a new one — the usual way to write a
    /// variation on a section you already like.
    func duplicatePattern(at index: Int) {
        guard song.canAddPattern, index < song.patterns.count else { return }
        var copy = song.patterns[index]
        copy.id = UUID()
        copy.name = song.nextPatternName()
        song.patterns.insert(copy, at: index + 1)
        song.arrangement.append(SongSection(patternID: copy.id))
        pushAll()
        pushArrangement()
        selectPattern(index + 1)
    }

    func removePattern(at index: Int) {
        guard song.patterns.count > 1, index < song.patterns.count else { return }
        let id = song.patterns[index].id
        song.patterns.remove(at: index)
        song.arrangement.removeAll { $0.patternID == id }
        pushAll()
        pushArrangement()
        selectPattern(min(index, song.patterns.count - 1))
    }

    func renamePattern(at index: Int, to name: String) {
        guard index < song.patterns.count else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        song.patterns[index].name = trimmed.isEmpty ? song.patterns[index].name : String(trimmed.prefix(6))
    }

    // MARK: Arrangement

    func addSection(patternID: UUID) {
        song.arrangement.append(SongSection(patternID: patternID))
        pushArrangement()
    }

    func removeSection(at offsets: IndexSet) {
        song.arrangement.remove(atOffsets: offsets)
        if song.arrangement.isEmpty, let first = song.patterns.first {
            song.arrangement = [SongSection(patternID: first.id)]
        }
        pushArrangement()
    }

    func moveSection(from offsets: IndexSet, to destination: Int) {
        song.arrangement.move(fromOffsets: offsets, toOffset: destination)
        pushArrangement()
    }

    func setSection(_ id: UUID, patternID: UUID) {
        guard let i = song.arrangement.firstIndex(where: { $0.id == id }) else { return }
        song.arrangement[i].patternID = patternID
        pushArrangement()
    }

    func setSection(_ id: UUID, repeats: Int) {
        guard let i = song.arrangement.firstIndex(where: { $0.id == id }) else { return }
        song.arrangement[i].repeats = min(max(repeats, 1), SongSection.maxRepeats)
        pushArrangement()
    }

    // MARK: Tracks

    /// Appends a track of `kind` and selects it. A song can hold several of the
    /// same kind — three pulses, two triangles — up to `Chip.maxTracks`.
    func addTrack(kind: ChannelKind) {
        guard song.canAddTrack else { return }
        song.tracks.append(Track(kind: kind))
        for i in song.patterns.indices { song.patterns[i].rows.append(Pattern.emptyRow) }
        pushAll()
        selectedTrack = song.tracks.count - 1
    }

    /// Copies a track's sound *and* its notes in every pattern, which is the
    /// quick way to build an octave double or a delayed echo line.
    func duplicateTrack(at index: Int) {
        guard song.canAddTrack, index < song.tracks.count else { return }
        var copy = song.tracks[index]
        copy.id = UUID()
        song.tracks.insert(copy, at: index + 1)
        for i in song.patterns.indices {
            let row = song.patterns[i].rows[safe: index] ?? Pattern.emptyRow
            song.patterns[i].rows.insert(row, at: min(index + 1, song.patterns[i].rows.count))
        }
        pushAll()
        selectedTrack = index + 1
    }

    func removeTrack(at index: Int) {
        guard song.tracks.count > 1, index < song.tracks.count else { return }
        song.tracks.remove(at: index)
        for i in song.patterns.indices where index < song.patterns[i].rows.count {
            song.patterns[i].rows.remove(at: index)
        }
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

    /// Autosave keeps the file on disk within a couple of seconds of the last
    /// edit; this forces it out now (backgrounding, opening another song).
    func saveNow() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        SongStore.shared.save(song, makeCurrent: true)
    }

    private func scheduleAutosave() {
        autosaveTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            SongStore.shared.save(self.song, makeCurrent: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        autosaveTimer = timer
    }

    func newSong() {
        stop()
        saveNow()
        song = Song(name: "Untitled")
        selectedPattern = 0
        pushAll()
        saveNow()
    }

    func open(_ other: Song) {
        stop()
        saveNow()
        var s = other
        s.normalize()
        song = s
        selectedPattern = 0
        songMode = false
        pushAll()
        engine.core.setSongMode(false)
        saveNow()
    }

    func duplicateSong() {
        saveNow()
        var copy = song
        copy.id = UUID()
        copy.name = song.name + " copy"
        open(copy)
    }

    /// Renders the WAV off the main thread; a long arrangement can take a
    /// while, and the render must not freeze the UI. `exportURL` clears at the
    /// start so observers see a fresh value when the file is ready.
    func export() {
        guard !isExporting else { return }
        isExporting = true
        exportURL = nil
        let song = song
        Task.detached(priority: .userInitiated) { [weak self] in
            let url = WavExport.render(song: song)
            await MainActor.run {
                guard let self else { return }
                self.exportURL = url
                self.isExporting = false
            }
        }
    }

    /// A short riff so the app makes noise the moment it opens.
    private func seedDemo() {
        song.name = "First Loop"
        song.tempo = 132
        let lead: [Int8] = [72, -1, 76, -1, 79, -1, 76, -1, 74, -1, 77, -1, 81, -1, 79, -1]
        let harmony: [Int8] = [-1, 64, -1, 67, -1, 64, -1, 67, -1, 65, -1, 69, -1, 65, -1, 62]
        let bass: [Int8] = [48, -1, -1, -1, 48, -1, -1, -1, 53, -1, -1, -1, 43, -1, -1, -1]
        let drums: [Int8] = [60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, 60, -1]
        for (i, notes) in [lead, harmony, bass, drums].enumerated() {
            for (step, n) in notes.enumerated() { song.patterns[0].rows[i][step] = n }
        }
    }
}
