import Foundation
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
    var selectedNote: Int8 = 60 {
        // Every way of choosing a pitch goes through this property, so
        // remembering it here is what keeps the on-screen keys and the typed
        // ones from disagreeing about what OFF should disarm to.
        didSet { if selectedNote >= 0 { lastPitch = selectedNote } }
    }
    /// The pitch OFF was armed over, so a second tap can put it back.
    @ObservationIgnored private var lastPitch: Int8 = 60
    /// Index into `song.tracks`, not a `ChannelKind`.
    var selectedTrack: Int = 0
    /// Step the grid cursor sits on. Paired with `selectedTrack`, this is the
    /// cell the hardware keyboard writes into.
    var selectedStep: Int = 0
    /// Octave the keys write in. Shared by the on-screen keyboard and the
    /// hardware one so the two can't drift apart and disagree about what
    /// pressing a key means.
    var octave: Int = 5
    /// A hardware key has been pressed. Until then the grid draws no cursor:
    /// with nothing to move it, a highlighted cell reads as a selection the
    /// user didn't make.
    var hardwareKeyboardInUse = false
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
    /// 0...1 while `isExporting`. A long arrangement takes real time, and a
    /// spinner with no end in sight reads as a hang.
    var exportProgress: Double = 0

    // MARK: Reported failures
    //
    // Each of these is a thing that used to fail silently. They're plain
    // strings rather than Errors because they exist to be shown to someone
    // who wants to know whether their song is safe, not to be pattern-matched.

    /// The export produced no file.
    var exportError: String?
    /// Audio wouldn't start, so nothing was going to be heard.
    var audioError: String?
    /// A save failed. The one that loses work.
    var storageError: String?

    /// Where songs are read and written. Injectable so tests get a temp
    /// directory instead of the real Documents folder.
    @ObservationIgnored var store: SongStore
    /// The offline WAV renderer. Injectable so a test can make export fail,
    /// stall, or report whatever progress it likes without needing a way to
    /// make the real renderer do those things.
    @ObservationIgnored var renderer: @Sendable (ExportRequest) -> ExportResult
    /// Seconds of quiet after the last edit before autosave fires. Tests turn
    /// autosave off entirely: a live timer makes editing tests order-dependent.
    @ObservationIgnored var autosaveInterval: TimeInterval = 1.5
    @ObservationIgnored var autosaveEnabled: Bool

    /// Readable by tests so they can assert the DSP core mirrors the model —
    /// the class of bug where an edit lands in `song` but never reaches audio.
    @ObservationIgnored private(set) var engine = AudioEngine()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var autosaveTimer: Timer?
    @ObservationIgnored private var sessionObserver: AudioSessionObserver?
    @ObservationIgnored private var exportCancel: CancelToken?

    init(store: SongStore = .shared,
         autosaveEnabled: Bool = true,
         // Wrapped in a closure rather than passed as `WavExport.render`: a
         // bare static-method reference isn't itself `@Sendable`, and the
         // implicit conversion is a warning.
         renderer: @escaping @Sendable (ExportRequest) -> ExportResult = { WavExport.render($0) }) {
        self.store = store
        self.autosaveEnabled = autosaveEnabled
        self.renderer = renderer
        // Reopen whatever was last on screen. Losing an unsaved loop to a
        // relaunch is not a thing this app should ever do, so every edit
        // autosaves and the last song is restored here.
        if let restored = store.loadLast() {
            song = restored
        } else {
            song = Song(name: "Untitled")
            seedDemo()
            save(song)
        }
        pushAll()
        observeAudioSession()
    }

    // MARK: Audio session

    /// The three ways the system silences a running engine. None of them are
    /// things the app does, and all of them leave PLAY lit over silence if
    /// they're ignored.
    private func observeAudioSession() {
        let observer = AudioSessionObserver()

        observer.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.stop()
            // The session is gone; drop the engine too so the restart below
            // actually does something rather than seeing `running == true`.
            self.engine.stopEngine()
        }

        observer.onInterruptionEnded = { [weak self] in
            // The engine comes back, the sequencer does not. A song that
            // starts playing by itself when a call ends is startling, and
            // there is no way to know the phone is still in someone's pocket.
            self?.engine.startIfNeeded()
        }

        observer.onOutputDeviceLost = { [weak self] in
            // Headphones out. Carrying on means the speaker suddenly blares.
            self?.stop()
        }

        observer.onMediaServicesReset = { [weak self] in
            guard let self else { return }
            self.stop()
            self.engine.stopEngine()
            // Every audio object the process holds is invalid now, so the
            // graph is rebuilt and the whole song pushed into it again.
            self.engine.buildEngine()
            self.pushAll()
            self.pushArrangement()
            self.pushTransport()
        }

        sessionObserver = observer
    }

    /// Stops the audio engine when the app leaves the foreground and nothing is
    /// playing. iOS suspends the process anyway without a background-audio
    /// mode, so this is tidiness rather than a behaviour change.
    func stopEngineIfIdle() {
        guard !isPlaying else { return }
        engine.stopEngine()
    }

    // MARK: Reporting

    /// Writes a song, surfacing a failure instead of dropping it.
    private func save(_ song: Song, makeCurrent: Bool = true) {
        do {
            try store.save(song, makeCurrent: makeCurrent)
            storageError = nil
        } catch {
            storageError = "Couldn't save “\(song.name)”. \(error.localizedDescription)"
        }
    }

    // MARK: Undo

    /// A point the editor can be put back to.
    ///
    /// The selection travels with the song deliberately: undoing a pattern
    /// delete has to put you back on the pattern you were editing, and
    /// `pushAll()` clamps both indices into whatever the *current* song allows,
    /// so they can't be recovered from the song alone.
    private struct Snapshot {
        var song: Song
        var selectedPattern: Int
        var selectedTrack: Int
    }

    /// A named run of edits that collapses to one undo step regardless of how
    /// long it takes. Distinct from time coalescing: typing a song name has no
    /// natural rhythm, so a wall-clock window would split a slow rename in two.
    enum CheckpointRun {
        case rename
    }

    /// `Song` is a value type whose arrays are copy-on-write, so a snapshot is
    /// a handful of retains rather than a copy of the notes. Observed — not
    /// `@ObservationIgnored` — so `canUndo`/`canRedo` invalidate the buttons.
    private var history = UndoHistory<Snapshot, CheckpointRun>()

    var undoCoalescingWindow: TimeInterval {
        get { history.coalescingWindow }
        set { history.coalescingWindow = newValue }
    }
    var undoLimit: Int {
        get { history.limit }
        set { history.limit = newValue }
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    private func snapshot() -> Snapshot {
        Snapshot(song: song,
                 selectedPattern: selectedPattern,
                 selectedTrack: selectedTrack)
    }

    /// Records the state *before* a mutation. Every mutating method below calls
    /// this as its first act. The folding rules live on `UndoHistory`.
    ///
    /// Deliberately not driven from `song.didSet`. `pushAll()` reassigns `song`
    /// (`song = s` after normalising), so a `didSet` hook would record a
    /// snapshot for every push — including the ones undo itself performs, which
    /// corrupts the stack the moment you undo twice.
    func checkpoint(coalescing: Bool = false, run: CheckpointRun? = nil) {
        history.record(snapshot(), coalescing: coalescing, run: run)
    }

    /// Ends the current named run, so the next edit of that kind starts a fresh
    /// undo step. Called when the name field gives up focus or is submitted.
    private func endCheckpointRun() {
        history.endRun()
    }

    func undo() {
        guard let previous = history.undo(current: snapshot()) else { return }
        apply(previous)
    }

    func redo() {
        guard let next = history.redo(current: snapshot()) else { return }
        apply(next)
    }

    private func apply(_ snapshot: Snapshot) {
        song = snapshot.song
        pushAll()
        pushArrangement()
        pushTransport()
        // After `pushAll` — it clamps both indices against the restored song,
        // which would otherwise throw away the selection we just recovered.
        selectedPattern = min(max(snapshot.selectedPattern, 0), song.patterns.count - 1)
        selectedTrack = min(max(snapshot.selectedTrack, 0), song.tracks.count - 1)
        // Straight assignment above, so `selectPattern`'s pin never runs. An
        // undo that put the cursor back only to have the next boundary take it
        // away again reads as the undo having failed.
        pinToSelectedPattern()
        engine.core.focus(pattern: selectedPattern)
        // Not `reconcileRingingVoices`: `pushAll` above reloads every pattern,
        // which drops each voice's record of the cell that started it. Nothing
        // is left to aim at, and any note still sounding may belong to a cell
        // the restored song no longer has.
        engine.core.releaseAll()
        if !songMode { playingPattern = selectedPattern }
        // The next edit starts a fresh coalescing window rather than folding
        // itself into whatever was undone. Same for a named run: typing after
        // an undo must not fold into the step the undo just restored.
        history.closeFolding()
    }

    private func resetHistory() {
        history.reset()
    }

    /// Stops the autosave and playhead timers. Tests call this in `tearDown`;
    /// a timer left on the main run loop outlives its test and fires into the
    /// next one.
    func invalidateTimers() {
        timer?.invalidate()
        timer = nil
        autosaveTimer?.invalidate()
        autosaveTimer = nil
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
        // A PLAY button that lights up over silence is worse than an error.
        guard engine.startIfNeeded() else {
            audioError = audioFailureMessage()
            return
        }
        audioError = nil
        pushAll()
        engine.core.setSongMode(songMode)
        engine.core.start()
        isPlaying = true
        // Each new play-through follows the arrangement again until the user
        // pins a pattern by selecting one.
        followsArrangement = true
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
            self.applyPlayhead(step: Int(self.engine.core.currentStep),
                               pattern: Int(self.engine.core.currentPattern))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One tick of the playhead: 60 a second from the timer above, and one at a
    /// time from the tests. Lifting it out of the closure is what makes the
    /// follow behaviour reachable without a run loop or a live audio engine.
    func applyPlayhead(step: Int, pattern: Int) {
        playhead = step
        guard playingPattern != pattern else { return }
        playingPattern = pattern
        // Following the arrangement means the grid should follow too, otherwise
        // you're watching a playhead run over the wrong notes. Unless the user
        // has pinned a pattern by selecting or editing one mid-playback — then
        // their pattern wins and only the playing dot moves.
        if songMode, followsArrangement, pattern < song.patterns.count {
            selectedPattern = pattern
        }
    }

    func setSongMode(_ on: Bool) {
        songMode = on
        engine.core.setSongMode(on)
        if !on { playingPattern = selectedPattern }
    }

    func setTempo(_ bpm: Double) {
        checkpoint(coalescing: true)
        song.tempo = bpm.clamped(to: Chip.tempoRange)
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
        pinToSelectedPattern()
        song.patterns[selectedPattern].rows[track][step] = note
        engine.core.setNote(pattern: selectedPattern, track: track, step: step, note: note)
        reconcileRingingVoices()
    }

    /// Cuts any voice whose originating cell no longer holds a note.
    ///
    /// A sustaining instrument has nothing else to stop it — no decay runs out
    /// and no pattern step comes along — so erasing the note that started it
    /// would otherwise leave it sounding until STOP.
    ///
    /// Aimed at the cell that actually started the note, not fired on any edit:
    /// clearing some later step on a track must not cut the note ringing from
    /// an earlier one. A cell overwritten with a *different* pitch is left
    /// alone too, since the sequencer retriggers it on the next pass.
    func reconcileRingingVoices() {
        for track in song.tracks.indices {
            guard let source = engine.core.ringingSource(track: track),
                  let note = song.patterns[safe: source.pattern]?
                      .rows[safe: track]?[safe: source.step],
                  note == Chip.emptyNote || note == Chip.noteOff
            else { continue }
            engine.core.release(track: track)
        }
    }

    /// Tap behaviour: an empty cell takes the selected note; a filled cell
    /// overwrites with the selected note, or clears if it already matches.
    func toggleCell(track: Int, step: Int) {
        checkpoint(coalescing: true)
        let existing = note(track: track, step: step)
        if existing == selectedNote {
            setNote(track: track, step: step, note: Chip.emptyNote)
        } else {
            setNote(track: track, step: step, note: selectedNote)
            audition(selectedNote, on: track)
        }
    }

    // MARK: Hardware keyboard
    //
    // An iPad is often a keyboard-and-trackpad machine, and a step sequencer
    // is one of the app types where that changes how it's used rather than
    // just how it's driven. Entering a run of notes is a cell tap plus a key
    // tap each, and typing them instead is the obvious faster path.

    /// Pulls the cursor back inside the grid. Both counts move under it — a
    /// pattern can be shortened, a track deleted — so every cursor operation
    /// starts here rather than trusting whoever wrote it last.
    func clampCursor() {
        selectedTrack = selectedTrack.clamped(to: 0...max(song.tracks.count - 1, 0))
        selectedStep = selectedStep.clamped(to: 0...max(patternLength - 1, 0))
    }

    /// Arrow-key movement. Stops at the edges rather than wrapping: an arrow
    /// held down should come to rest somewhere predictable.
    func moveCursor(track trackDelta: Int = 0, step stepDelta: Int = 0) {
        hardwareKeyboardInUse = true
        clampCursor()
        selectedTrack = (selectedTrack + trackDelta)
            .clamped(to: 0...max(song.tracks.count - 1, 0))
        selectedStep = (selectedStep + stepDelta)
            .clamped(to: 0...max(patternLength - 1, 0))
    }

    /// Follows a tap, but only once the keyboard is in play. A touch-only
    /// session never sees the cursor, so moving it would be invisible; a mixed
    /// one would otherwise have taps and arrows disagreeing about where "here"
    /// is.
    func placeCursor(track: Int, step: Int) {
        guard hardwareKeyboardInUse else { return }
        selectedTrack = track
        selectedStep = step
        clampCursor()
    }

    /// Writes a note at the cursor and steps down, the way a tracker does.
    /// Typing a run of notes is the whole point, and reaching for an arrow key
    /// between each one would give most of it back.
    func typeNote(_ note: Int8) {
        hardwareKeyboardInUse = true
        clampCursor()
        guard !song.tracks.isEmpty else { return }
        checkpoint(coalescing: true)
        setNote(track: selectedTrack, step: selectedStep, note: note)
        selectedNote = note
        audition(note)
        advanceCursor()
    }

    /// Empties the cell under the cursor and steps down, so holding delete
    /// walks a run of notes off the same way typing walked it on.
    func clearAtCursor() {
        hardwareKeyboardInUse = true
        clampCursor()
        guard !song.tracks.isEmpty else { return }
        checkpoint(coalescing: true)
        setNote(track: selectedTrack, step: selectedStep, note: Chip.emptyNote)
        advanceCursor()
    }

    /// Wraps, unlike the arrow keys: this one runs off the end of a pattern
    /// you're filling in, and stopping dead on the last step would mean
    /// reaching for the mouse to carry on.
    func advanceCursor() {
        guard patternLength > 0 else { return }
        selectedStep = (selectedStep + 1) % patternLength
    }

    /// The octaves the keyboard can reach — one source for `shiftOctave` and
    /// for the buttons that grey out at the ends.
    static let octaveRange = 0...8

    /// Shared by the on-screen octave buttons and the hardware ones. The range
    /// is the one the on-screen keyboard has always offered.
    func shiftOctave(_ delta: Int) {
        octave = (octave + delta).clamped(to: Studio.octaveRange)
    }

    /// Whether the keyboard is about to write a note off rather than a pitch.
    /// The readout leans on this to explain what OFF does at the one moment
    /// anyone needs to know.
    var noteOffArmed: Bool { selectedNote == Chip.noteOff }

    /// Arms a note off, or disarms back to the pitch it was armed over.
    ///
    /// The arm used to be one-way, which left tapping some other key as the
    /// only way out — so the button read as a toggle that had jammed.
    func toggleNoteOff() {
        selectedNote = selectedNote == Chip.noteOff ? lastPitch : Chip.noteOff
    }

    /// The note a track header's tap demos, or nil when there's nothing to
    /// play. Split out from `previewTrack` because what it picks is the whole
    /// substance of the feature and rendering audio to assert on it is a slow,
    /// indirect way to ask.
    func previewNote(forTrack index: Int) -> Int8? {
        // Muted tracks return early, which reads as cosmetic and isn't:
        // `audition` marks the voice it takes as having no originating cell,
        // and that record is what `reconcileRingingVoices` needs to release a
        // held note. Previewing a muted track would be a silent no-op that
        // strands the next sustained note on it. The mute speaker sits right
        // under the name, so the silence explains itself.
        guard let track = song.tracks[safe: index], !track.muted else { return nil }
        // Noise has no melody — the LFSR runs off the note's frequency, so a
        // bass C2 is a slow rattle rather than the drum the track plays. And an
        // armed OFF is not a pitch at all; the core drops the sentinel, which
        // would leave the header dead at seemingly random times.
        if track.kind == .noise { return Chip.defaultPreviewNote }
        return selectedNote >= 0 ? selectedNote : Chip.defaultPreviewNote
    }

    /// Demos a track's sound. The tester tapped the top row expecting to hear
    /// what each channel sounded like, and nothing happened.
    func previewTrack(_ index: Int) {
        guard let note = previewNote(forTrack: index) else { return }
        audition(note, on: index)
    }

    /// Plays the note already in a cell. Writes nothing, arms nothing, moves
    /// nothing — a beta tester had no way to hear what was in a cell except by
    /// tapping it, and tapping it wrote over it.
    ///
    /// Empty and OFF cells are turned away here rather than left to the core's
    /// own `note >= 0` guard. `audition` starts the audio engine on its way
    /// through and can raise an error doing it, so leaning on the core would
    /// make previewing an empty cell inaudible but not harmless.
    ///
    /// Reports whether anything was played, which is what the tests assert on.
    @discardableResult
    func previewCell(track: Int, step: Int) -> Bool {
        let note = self.note(track: track, step: step)
        // An OFF has no sound of its own, and releasing the track's voice to
        // demonstrate it would be an audible change from a read-only gesture.
        guard note != Chip.emptyNote, note != Chip.noteOff else { return false }
        audition(note, on: track)
        return true
    }

    /// Previews a note on a track — the selected one unless told otherwise.
    func audition(_ note: Int8, on track: Int? = nil) {
        guard engine.startIfNeeded() else {
            audioError = audioFailureMessage()
            return
        }
        audioError = nil
        engine.core.audition(track: track ?? selectedTrack, note: note)
    }

    private func audioFailureMessage() -> String {
        let detail = engine.lastError.map { " \($0.localizedDescription)" } ?? ""
        return "Couldn't start audio.\(detail)"
    }

    /// Clears one track in the pattern being edited.
    func clearTrack(_ track: Int) {
        guard track < song.tracks.count else { return }
        checkpoint()
        erase(track)
    }

    private func erase(_ track: Int) {
        guard selectedPattern < song.patterns.count,
              track < song.tracks.count else { return }
        // Batched like `clearPattern(at:)`: one pin, one reconcile pass at the
        // end — not one per step via `setNote`.
        pinToSelectedPattern()
        for step in 0..<Chip.maxSteps {
            song.patterns[selectedPattern].rows[track][step] = Chip.emptyNote
            engine.core.setNote(pattern: selectedPattern, track: track, step: step,
                                note: Chip.emptyNote)
        }
        reconcileRingingVoices()
    }

    /// Clears every track in the pattern being edited. Other patterns are left
    /// alone — the arrangement is the song, so this is not "clear everything".
    func clearPattern() {
        clearPattern(at: selectedPattern)
    }

    /// Clears every track in one pattern without moving the editor to it —
    /// clearing B from its chip menu must not yank the grid off the pattern
    /// being edited.
    func clearPattern(at index: Int) {
        guard index < song.patterns.count else { return }
        // One checkpoint for the lot — a per-track checkpoint would make
        // undoing a cleared pattern take one press per track.
        checkpoint()
        // Only when it's the pattern on screen. Clearing B from its chip menu
        // doesn't move the editor off A, so it has no business pinning A.
        if index == selectedPattern { pinToSelectedPattern() }
        for track in 0..<song.tracks.count {
            for step in 0..<Chip.maxSteps {
                song.patterns[index].rows[track][step] = Chip.emptyNote
                engine.core.setNote(pattern: index, track: track, step: step, note: Chip.emptyNote)
            }
        }
        reconcileRingingVoices()
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

    /// True while SONG-mode playback should drag the grid along with the
    /// sequencer. Selecting a pattern or editing one turns it off for the rest
    /// of the play-through so editing isn't yanked away at the next boundary;
    /// selecting the pattern that's currently sounding turns it back on.
    @ObservationIgnored private(set) var followsArrangement = true

    /// Keeps the grid on the pattern being edited for the rest of the
    /// play-through. Editing counts as claiming a pattern just as much as
    /// selecting one does — otherwise writing a note over playback lasts only
    /// until the next arrangement boundary hauls the grid somewhere else.
    ///
    /// Deliberately not called from instrument, tempo, or arrangement edits.
    /// Those aren't pattern-local — an instrument sounds in every pattern — so
    /// being carried along doesn't interrupt them.
    private func pinToSelectedPattern() {
        if isPlaying, songMode { followsArrangement = false }
    }

    func selectPattern(_ index: Int) {
        guard index >= 0, index < song.patterns.count else { return }
        // Jumping to the pattern that's already sounding means "back to the
        // song", and re-arms; any other choice pins the grid there.
        if isPlaying, songMode { followsArrangement = (index == playingPattern) }
        selectedPattern = index
        engine.core.focus(pattern: index)
        if !songMode { playingPattern = index }
    }

    func setPatternLength(_ length: Int) {
        guard selectedPattern < song.patterns.count else { return }
        checkpoint(coalescing: true)
        pinToSelectedPattern()
        song.patterns[selectedPattern].length = length.clamped(to: Chip.patternLengthRange)
        engine.core.setLength(pattern: selectedPattern, length: song.patterns[selectedPattern].length)
    }

    /// Adds an empty pattern, appends it to the arrangement, and starts editing it.
    @discardableResult
    func addPattern() -> Int? {
        guard song.canAddPattern else { return nil }
        checkpoint()
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
        checkpoint()
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
        checkpoint()
        let id = song.patterns[index].id
        song.patterns.remove(at: index)
        song.arrangement.removeAll { $0.patternID == id }
        pushAll()
        pushArrangement()
        selectPattern(min(index, song.patterns.count - 1))
    }

    func renamePattern(at index: Int, to name: String) {
        guard index < song.patterns.count,
              let accepted = acceptablePatternName(name, for: index) else { return }
        checkpoint()
        song.patterns[index].name = accepted
    }

    /// The name a rename would actually store — trimmed and truncated — or nil
    /// when it's empty or collides with another pattern's name. Two chips both
    /// labelled "A" are indistinguishable in the strip, the ••• menu, and to
    /// VoiceOver, so duplicates are refused. The UI uses this to disable the
    /// Rename button rather than letting it silently do nothing.
    func acceptablePatternName(_ name: String, for index: Int) -> String? {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(6))
        guard !trimmed.isEmpty else { return nil }
        let taken = song.patterns.enumerated().contains { $0.offset != index && $0.element.name == trimmed }
        return taken ? nil : trimmed
    }

    // MARK: Arrangement

    func addSection(patternID: UUID) {
        checkpoint()
        song.arrangement.append(SongSection(patternID: patternID))
        pushArrangement()
    }

    func removeSection(at offsets: IndexSet) {
        checkpoint()
        song.arrangement.remove(atOffsets: offsets)
        if song.arrangement.isEmpty, let first = song.patterns.first {
            song.arrangement = [SongSection(patternID: first.id)]
        }
        pushArrangement()
    }

    func moveSection(from offsets: IndexSet, to destination: Int) {
        checkpoint()
        song.arrangement.move(fromOffsets: offsets, toOffset: destination)
        pushArrangement()
    }

    func setSection(_ id: UUID, patternID: UUID) {
        guard let i = song.arrangement.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        song.arrangement[i].patternID = patternID
        pushArrangement()
    }

    func setSection(_ id: UUID, repeats: Int) {
        guard let i = song.arrangement.firstIndex(where: { $0.id == id }) else { return }
        checkpoint(coalescing: true)
        song.arrangement[i].repeats = repeats.clamped(to: 1...SongSection.maxRepeats)
        pushArrangement()
    }

    // MARK: Tracks

    /// Appends a track of `kind` and selects it. A song can hold several of the
    /// same kind — three pulses, two triangles — up to `Chip.maxTracks`.
    func addTrack(kind: ChannelKind) {
        guard song.canAddTrack else { return }
        checkpoint()
        song.tracks.append(Track(kind: kind))
        for i in song.patterns.indices { song.patterns[i].rows.append(Pattern.emptyRow) }
        pushAll()
        selectedTrack = song.tracks.count - 1
    }

    /// Copies a track's sound *and* its notes in every pattern, which is the
    /// quick way to build an octave double or a delayed echo line.
    func duplicateTrack(at index: Int) {
        guard song.canAddTrack, index < song.tracks.count else { return }
        checkpoint()
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
        checkpoint()
        song.tracks.remove(at: index)
        for i in song.patterns.indices where index < song.patterns[i].rows.count {
            song.patterns[i].rows.remove(at: index)
        }
        pushAll()
        // After `pushAll` — `load` acks any outstanding release, so one issued
        // before it would be swallowed. Every voice from `index` up now belongs
        // to a different track, so there is nothing sensible to aim at.
        engine.core.releaseAll()
        selectedTrack = min(selectedTrack, song.tracks.count - 1)
    }

    /// Switches a track's waveform, keeping its notes. Volume/decay/duty come
    /// from the new kind's defaults, since a bass triangle's envelope makes no
    /// sense on noise.
    func setKind(_ kind: ChannelKind, for index: Int) {
        guard index < song.tracks.count, song.tracks[index].kind != kind else { return }
        checkpoint()
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
        save(song)
    }

    private func scheduleAutosave() {
        guard autosaveEnabled else { return }
        autosaveTimer?.invalidate()
        let timer = Timer(timeInterval: autosaveInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.save(self.song)
        }
        RunLoop.main.add(timer, forMode: .common)
        autosaveTimer = timer
    }

    func newSong() {
        stop()
        saveNow()
        resetHistory()
        song = Song(name: "Untitled")
        selectedPattern = 0
        pushAll()
        saveNow()
    }

    func open(_ other: Song) {
        stop()
        saveNow()
        // Undo does not reach across songs: restoring a snapshot of a song you
        // are no longer editing would silently replace the one you are.
        resetHistory()
        var s = other
        s.normalize()
        song = s
        selectedPattern = 0
        songMode = false
        pushAll()
        engine.core.setSongMode(false)
        saveNow()
    }

    /// Renames a song in the library.
    ///
    /// If it's the song currently on screen the open copy is renamed too —
    /// writing straight to the store would work for a moment and then be
    /// overwritten by the next autosave, which still holds the old name.
    func rename(_ other: Song, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if other.id == song.id {
            // One step, not folded into whatever came before: a rename from the
            // library is a single deliberate act, unlike typing in the title bar.
            guard trimmed != song.name else { return }
            checkpoint()
            song.name = trimmed
            saveNow()
        } else {
            var copy = other
            copy.name = trimmed
            save(copy, makeCurrent: false)
        }
    }

    /// Renames the open song as it's typed.
    ///
    /// Writes straight through to the model rather than holding a draft in the
    /// view: undo restores a snapshot of the *same* song, so a view-side draft
    /// has no id change to resynchronise on and would re-commit the name the
    /// undo just removed. Keeping the model authoritative also means autosave
    /// and a background-kill see the name the user can see.
    ///
    /// No trimming here — rejecting whitespace mid-word makes a space
    /// untypeable. `normalizeSongName()` cleans up when editing ends.
    func setSongName(_ name: String) {
        guard name != song.name else { return }
        checkpoint(run: .rename)
        song.name = name
    }

    /// Ends a title-bar rename: trims, restores the previous name if what's
    /// left is empty, and closes the run so the next rename is its own step.
    func normalizeSongName() {
        defer { endCheckpointRun() }
        let trimmed = song.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // Undoing rather than substituting a placeholder: the name before
            // the edit is the one the user last chose, and it's already on the
            // stack. The redo entry that undo just pushed is dropped — the
            // empty name was rejected, and Redo must not reinstate it.
            if history.lastRunIs(.rename) {
                undo()
                history.dropRedo()
            }
            return
        }
        if trimmed != song.name { song.name = trimmed }
        saveNow()
    }

    func delete(_ other: Song) {
        do {
            try store.delete(other)
        } catch {
            // The file is still there, so the song is still real — leave the
            // editor and library alone and say what happened.
            storageError = "Couldn't delete “\(other.name)”. \(error.localizedDescription)"
            return
        }
        // Deleting the song on screen: the editor has to move off it, or the
        // next autosave writes the "deleted" song straight back to disk.
        guard other.id == song.id else { return }
        stop()
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        resetHistory()
        if var next = store.loadAll().first(where: { $0.id != other.id }) {
            next.normalize()
            song = next
        } else {
            song = Song(name: "Untitled")
        }
        selectedPattern = 0
        songMode = false
        pushAll()
        engine.core.setSongMode(false)
        save(song)
    }

    // MARK: Sharing

    /// Set when an import fails, for the library to alert on.
    var importError: String?
    /// Set when preparing a song to share fails. Separate from `importError`
    /// because the two alert under different titles — a share failure reported
    /// as "Import failed" is just wrong.
    var shareError: String?
    /// A `.chipsong` file written out and waiting to be shared.
    var shareURL: URL?

    /// Writes `other` out as a `.chipsong` and publishes the URL for a share
    /// sheet to pick up.
    func share(_ other: Song) {
        do {
            shareURL = try SongDocument.write(other)
            // A share that works clears the last one that didn't; otherwise a
            // stale alert fires on the next unrelated state change.
            shareError = nil
        } catch {
            shareError = "Couldn't prepare “\(other.name)” to share. \(error.localizedDescription)"
        }
    }

    /// Imports a song from a file and opens it.
    ///
    /// The file is arbitrary JSON from outside the app, so it goes through
    /// `SongDocument` (which normalises) and through the collision check
    /// (so an imported song can't overwrite one already in the library).
    @discardableResult
    func importSong(from url: URL) -> Bool {
        do {
            let decoded = try SongDocument.read(contentsOf: url)
            let existing = store.loadAll().map(\.id)
            let song = SongDocument.resolvingCollision(decoded, against: existing)
            save(song, makeCurrent: false)
            open(song)
            importError = nil
            return true
        } catch {
            importError = error.localizedDescription
            return false
        }
    }

    /// Copies a song in the library without opening it.
    func duplicate(_ other: Song) {
        var copy = other
        copy.id = UUID()
        copy.name = other.name + " copy"
        save(copy, makeCurrent: false)
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
    func export(options: ExportOptions = ExportOptions()) {
        guard !isExporting else { return }
        isExporting = true
        exportURL = nil
        exportError = nil
        exportProgress = 0

        let token = CancelToken()
        exportCancel = token
        let song = song
        // Captured before the detached task so the closure reads the injected
        // renderer rather than reaching back through `self` off the main actor.
        let renderer = renderer

        // Both closures capture self weakly *here*, while it is still the
        // method's immutable `self`. Swift 6 (the CI compiler) rejects a
        // nested concurrent closure reading a `[weak self]` captured by the
        // detached task — that capture is a var — so nothing inside the
        // detach may name `self` at all.
        let progress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.exportProgress = fraction }
        }
        let finish: @MainActor @Sendable (ExportResult) -> Void = { [weak self] result in
            guard let self else { return }
            self.isExporting = false
            self.exportProgress = 0
            self.exportCancel = nil
            switch result {
            case .success(let url):
                self.exportURL = url
            case .cancelled:
                // Deliberately silent. Cancelling is not failing, and an
                // alert for something the user just asked to stop is noise.
                break
            case .failed:
                self.exportError = "Couldn't export “\(song.name)”. There may not be enough space on the device."
            }
        }

        Task.detached(priority: .userInitiated) {
            let result = renderer(ExportRequest(
                song: song,
                options: options,
                progress: progress,
                isCancelled: { token.isCancelled }))
            await MainActor.run { finish(result) }
        }
    }

    /// Abandons a running export. The renderer notices at its next chunk
    /// boundary and cleans up whatever it had written.
    func cancelExport() {
        exportCancel?.cancel()
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

/// A cancellation flag shared between the main actor and the render thread.
///
/// Locked rather than a bare `Bool`: the render polls it from a detached task
/// while the main actor sets it, and the whole point of the flag is that the
/// write is seen promptly.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
