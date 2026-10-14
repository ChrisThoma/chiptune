package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.ChipCore
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.ExportRequest
import dev.individuation.chiptune.core.audio.ExportResult
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.PatternNameCheck
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDecodeException
import dev.individuation.chiptune.core.model.SongDocument
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.model.Track
import dev.individuation.chiptune.core.model.swiftClamp
import dev.individuation.chiptune.core.store.SongLibrary
import dev.individuation.chiptune.core.store.SongStore
import dev.individuation.chiptune.core.store.UnreadableSongs
import dev.individuation.chiptune.core.text.Graphemes
import dev.individuation.chiptune.core.text.SwiftText
import java.io.File
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * App-wide state: the song being edited, the DSP core it plays through, and
 * the editing cursor. Port of `Sources/Model/Studio.swift`. Every mutation
 * pushes the relevant slice down to [core].
 *
 * Read state reaches the UI as [state], one immutable [StudioState] replaced
 * atomically on every change. The properties below read and write it too, so
 * code ported from Swift (and the tests) can say `studio.selectedNote = 64`.
 *
 * Not thread-safe: call it from one thread (the main thread in the app). The
 * export renderer runs on [exportExecutor] and hands its result back through
 * [Scheduler.post].
 */
class Studio(
    /** Where songs are read and written. */
    val store: SongStore,
    /** The live output; the platform implementation pulls from [core]. */
    val audio: AudioOutput,
    private val scheduler: Scheduler,
    /** Tests turn autosave off: a live timer makes editing tests order-dependent. */
    var autosaveEnabled: Boolean = true,
    /** The offline renderer, WAV or MIDI by the options' format; injectable so a test can make export fail,
     * stall or report whatever progress it likes. The app passes
     * `{ ExportRenderer.render(it, cacheDir) }`. */
    var renderer: (ExportRequest) -> ExportResult,
    /** Runs [renderer] off the Studio's thread. */
    private val exportExecutor: Executor,
    /** Writes `.chipsong` files for [share]. */
    private val shareWriter: SongShareWriter,
    /** The DSP core every edit is mirrored into. Built at the output's rate. */
    val core: ChipCore = ChipCore(44100.0),
) {
    /** A point the editor can be put back to. The selection travels with the
     * song: `pushAll` clamps both indices into the current song, so they can't
     * be recovered from the song alone. */
    private data class Snapshot(val song: Song, val selectedPattern: Int, val selectedTrack: Int)

    /** Where SONG playback is, in terms that survive a renumbering. */
    private data class SoundingPosition(
        val patternID: UUID,
        val sectionID: UUID,
        /** Which play of the section's repeats, counted from its first slot. */
        val offset: Int,
        /** The sections after it, in order: who takes over if it is deleted. */
        val followingSectionIDs: List<UUID>,
    )

    private val history = UndoHistory<Snapshot, CheckpointRun, CheckpointKind>(scheduler::now)

    /** The pitch OFF was armed over, so a second tap can put it back. */
    private var lastPitch = 60
    private var playheadTimer: Cancellable? = null
    private var autosaveTimer: Cancellable? = null
    private var exportCancel: AtomicBoolean? = null

    /** True while SONG playback should drag the grid along with the sequencer.
     * Selecting or editing a pattern turns it off for the rest of the
     * play-through; selecting the sounding pattern turns it back on. */
    var followsArrangement: Boolean = true
        private set

    /** Seconds of quiet after the last edit before autosave fires. */
    var autosaveInterval: Double = 1.5

    private val mutableState: MutableStateFlow<StudioState>

    /** Everything the UI reads, replaced atomically on each change. */
    val state: StateFlow<StudioState>

    init {
        // Reopen whatever was last on screen; an empty library gets the demo.
        val launchLibrary = store.loadLibrary()
        val restored = store.loadLast()
        mutableState = MutableStateFlow(StudioState(song = restored ?: seededDemo()))
        state = mutableState.asStateFlow()
        if (restored == null) save(song)
        noteUnreadable(launchLibrary)
        pushAll()
    }

    private inline fun update(transform: (StudioState) -> StudioState) {
        mutableState.value = transform(mutableState.value)
    }

    // MARK: State, as properties

    /** The song being edited. A new id pushes the whole song to the core; any
     * change schedules an autosave. */
    var song: Song
        get() = mutableState.value.song
        set(value) {
            val old = mutableState.value.song
            update { it.copy(song = value) }
            if (value.id != old.id) pushAll()
            if (value != old) scheduleAutosave()
        }

    /** Every way of choosing a pitch goes through here, which is what keeps
     * the on-screen keys and the typed ones agreeing on what OFF disarms to. */
    var selectedNote: Int
        get() = mutableState.value.selectedNote
        set(value) {
            update { it.copy(selectedNote = value) }
            if (value >= 0) lastPitch = value
        }

    var selectedTrack: Int
        get() = mutableState.value.selectedTrack
        set(value) = update { it.copy(selectedTrack = value) }

    var selectedStep: Int
        get() = mutableState.value.selectedStep
        set(value) = update { it.copy(selectedStep = value) }

    var octave: Int
        get() = mutableState.value.octave
        set(value) = update { it.copy(octave = value) }

    var hardwareKeyboardInUse: Boolean
        get() = mutableState.value.hardwareKeyboardInUse
        set(value) = update { it.copy(hardwareKeyboardInUse = value) }

    val dismissRequests: Int get() = mutableState.value.dismissRequests

    val revealRequest: RevealRequest get() = mutableState.value.revealRequest

    var selectedPattern: Int
        get() = mutableState.value.selectedPattern
        set(value) = update { it.copy(selectedPattern = value) }

    /** The raw flag; [setSongMode] also tells the core. */
    @set:JvmName("assignSongMode")
    var songMode: Boolean
        get() = mutableState.value.songMode
        set(value) = update { it.copy(songMode = value) }

    var isPlaying: Boolean
        get() = mutableState.value.isPlaying
        set(value) = update { it.copy(isPlaying = value) }

    var playhead: Int
        get() = mutableState.value.playhead
        set(value) = update { it.copy(playhead = value) }

    var playingPattern: Int
        get() = mutableState.value.playingPattern
        set(value) = update { it.copy(playingPattern = value) }

    var playingSection: Int
        get() = mutableState.value.playingSection
        set(value) = update { it.copy(playingSection = value) }

    var exportOptions: ExportOptions
        get() = mutableState.value.exportOptions
        set(value) = update { it.copy(exportOptions = value) }

    var exportFile: File?
        get() = mutableState.value.exportFile
        set(value) = update { it.copy(exportFile = value) }

    val isExporting: Boolean get() = mutableState.value.isExporting

    val exportProgress: Double get() = mutableState.value.exportProgress

    val completedExportAttempt: Int get() = mutableState.value.completedExportAttempt

    var exportError: String?
        get() = mutableState.value.exportError
        set(value) = update { it.copy(exportError = value) }

    var audioError: String?
        get() = mutableState.value.audioError
        set(value) = update { it.copy(audioError = value) }

    var storageError: String?
        get() = mutableState.value.storageError
        set(value) = update { it.copy(storageError = value) }

    var deleteError: String?
        get() = mutableState.value.deleteError
        set(value) = update { it.copy(deleteError = value) }

    var unreadableSongsNotice: String?
        get() = mutableState.value.unreadableSongsNotice
        set(value) = update { it.copy(unreadableSongsNotice = value) }

    var importError: String?
        get() = mutableState.value.importError
        set(value) = update { it.copy(importError = value) }

    var shareError: String?
        get() = mutableState.value.shareError
        set(value) = update { it.copy(shareError = value) }

    var shareFile: File?
        get() = mutableState.value.shareFile
        set(value) = update { it.copy(shareFile = value) }

    val songBoundPresenters: SongBoundPresenters get() = mutableState.value.songBoundPresenters

    /** Reported by the views that own a song-bound dialog or sheet. */
    fun setPresented(surface: SongBoundPresenters.Surface, presented: Boolean) =
        update { it.copy(songBoundPresenters = it.songBoundPresenters.set(surface, presented)) }

    val canUndo: Boolean get() = mutableState.value.canUndo
    val canRedo: Boolean get() = mutableState.value.canRedo
    val noteOffArmed: Boolean get() = mutableState.value.noteOffArmed
    val selectedKind: ChannelKind get() = mutableState.value.selectedKind
    val pattern: Pattern get() = mutableState.value.pattern
    val patternLength: Int get() = mutableState.value.patternLength

    var undoCoalescingWindow: Double
        get() = history.coalescingWindow
        set(value) {
            history.coalescingWindow = value
        }

    var undoLimit: Int
        get() = history.limit
        set(value) {
            history.limit = value
        }

    private fun syncHistory() {
        val undo = history.canUndo
        val redo = history.canRedo
        if (undo != canUndo || redo != canRedo) update { it.copy(canUndo = undo, canRedo = redo) }
    }

    // MARK: Library

    /** Loads the library and reports any file not reported before. */
    fun loadLibrary(): List<Song> {
        val library = store.loadLibrary()
        noteUnreadable(library)
        return library.songs
    }

    private fun noteUnreadable(library: SongLibrary) {
        val fresh = store.claimUnreported(library)
        if (fresh > 0) unreadableSongsNotice = UnreadableSongs.message(fresh)
    }

    // MARK: Audio events

    /** Audio focus lost (iOS: interruption began). The output is dropped too,
     * so the restart on regaining focus actually does something. */
    fun onAudioFocusLost() {
        stop()
        audio.stopEngine()
    }

    /** Focus regained: the output comes back, the sequencer does not. A song
     * that starts by itself when a call ends is startling. */
    fun onAudioFocusGained() {
        audio.startIfNeeded()
    }

    /** Headphones out: carrying on would blare from the speaker. */
    fun onBecomingNoisy() {
        stop()
    }

    /** The output died (iOS: media services reset). Rebuilt, and the whole
     * song pushed in again, or the app comes back alive and silent. */
    fun onAudioOutputDead() {
        stop()
        audio.stopEngine()
        audio.rebuild()
        pushAll()
        pushArrangement()
        pushTransport()
    }

    /** Leaving the foreground: playback goes through [stop] so the transport
     * stops claiming it's playing, then the output stops. */
    fun stopEngineForBackground() {
        if (isPlaying) stop()
        audio.stopEngine()
    }

    // MARK: Saving

    /** Writes a song, surfacing a failure instead of dropping it. */
    private fun save(song: Song, makeCurrent: Boolean = true): Boolean = try {
        store.save(song, makeCurrent)
        storageError = null
        true
    } catch (e: Exception) {
        storageError = WriteFailureMessage.save(song.name, e)
        false
    }

    // MARK: Undo

    private fun snapshot() = Snapshot(song, selectedPattern, selectedTrack)

    /** Records the state before a mutation; every mutating method calls this
     * first. Not driven from the song setter: `pushAll` reassigns the song,
     * and undo itself would then record steps. */
    fun checkpoint(coalescing: Boolean = false, kind: CheckpointKind? = null, run: CheckpointRun? = null) {
        history.record(snapshot(), coalescing, kind, run)
        syncHistory()
    }

    /** The keyboard asking for whatever is on screen to close. */
    fun requestDismiss() = update { it.copy(dismissRequests = it.dismissRequests + 1) }

    fun undo() {
        val previous = history.undo(snapshot()) ?: return
        restoreSnapshot(previous)
    }

    fun redo() {
        val next = history.redo(snapshot()) ?: return
        restoreSnapshot(next)
    }

    private fun restoreSnapshot(snapshot: Snapshot) {
        // Undo renumbers patterns and chain slots just as the edits it
        // reverses did, so the sequencer is re-aimed the same way.
        val sounding = soundingPosition()
        song = snapshot.song
        pushAll()
        pushArrangement()
        pushTransport()
        // After pushAll, which clamps both indices against the restored song.
        selectedPattern = swiftClamp(snapshot.selectedPattern, 0, song.patterns.size - 1)
        selectedTrack = swiftClamp(snapshot.selectedTrack, 0, song.tracks.size - 1)
        // An undo that the next boundary took away would read as a failed undo.
        pinToSelectedPattern()
        core.focus(selectedPattern)
        // pushAll reloaded every pattern, so nothing is left to aim a
        // reconcile at; any note still sounding may be from a cell that's gone.
        core.releaseAll()
        restore(sounding)
        if (!songMode) playingPattern = selectedPattern
        history.closeFolding()
        syncHistory()
        update { it.copy(revealRequest = it.revealRequest.bumped(RevealRequest.Reason.UNDO_REDO)) }
    }

    /** Stops the autosave and playhead timers. */
    fun invalidateTimers() {
        playheadTimer?.cancel()
        playheadTimer = null
        autosaveTimer?.cancel()
        autosaveTimer = null
    }

    // MARK: Transport

    fun togglePlay() = if (isPlaying) stop() else play()

    fun play() {
        // A PLAY button that lights up over silence is worse than an error.
        if (!audio.startIfNeeded()) {
            audioError = AudioFailureMessage.start(audio.lastError)
            return
        }
        audioError = null
        pushAll()
        core.setSongMode(songMode)
        armSongFollow()
        core.start()
        isPlaying = true
        followsArrangement = true
        playingSection = 0
        startPlayheadTimer()
    }

    /** SONG Play starts from the head of the arrangement whatever played
     * before: re-seeds the playing pattern and moves the grid there now. */
    fun armSongFollow() {
        if (!songMode) return
        followsArrangement = true
        val head = song.chain.firstOrNull() ?: return
        if (head >= song.patterns.size) return
        playingPattern = head
        playingSection = 0
        selectedPattern = head
        core.focus(head)
        clampCursor()
    }

    fun stop() {
        core.stop()
        isPlaying = false
        playheadTimer?.cancel()
        playheadTimer = null
        playhead = 0
    }

    private fun startPlayheadTimer() {
        playheadTimer?.cancel()
        playheadTimer = scheduler.scheduleRepeating(1.0 / 60.0) {
            applyPlayhead(core.currentStep, core.currentPattern, core.currentChainSlot)
        }
    }

    /** One tick of the playhead: 60 a second from the poll, one at a time
     * from the tests. */
    fun applyPlayhead(step: Int, pattern: Int, slot: Int? = null) {
        playhead = step
        // Before the pattern guard: a section's repeats play the same pattern.
        if (songMode && slot != null) song.sectionIndex(slot)?.let { playingSection = it }
        if (playingPattern == pattern) return
        playingPattern = pattern
        // Following the arrangement means the grid follows too, unless the
        // user has pinned a pattern by selecting or editing one.
        if (songMode && followsArrangement && pattern < song.patterns.size) selectedPattern = pattern
    }

    fun setSongMode(on: Boolean) {
        songMode = on
        core.setSongMode(on)
        if (!on) playingPattern = selectedPattern
    }

    fun setTempo(bpm: Double) {
        if (bpm.isNaN()) return
        val clamped = swiftClamp(bpm, Chip.TEMPO_MIN, Chip.TEMPO_MAX)
        // A write that changes nothing is not an edit (it would wipe Redo).
        if (clamped == song.tempo) return
        checkpoint(coalescing = true, kind = CheckpointKind.Tempo)
        song = song.copy(tempo = clamped)
        pushTransport()
    }

    // MARK: Editing

    fun note(track: Int, step: Int): Int =
        pattern.rows.getOrNull(track)?.getOrNull(step) ?: Chip.EMPTY_NOTE

    /** Writes a note into the grid and mirrors it into the live pattern so it
     * is heard on the next pass. */
    fun setNote(track: Int, step: Int, note: Int) {
        if (selectedPattern !in song.patterns.indices || track !in song.tracks.indices ||
            step !in 0 until Chip.MAX_STEPS
        ) return
        pinToSelectedPattern()
        song = song.withNote(selectedPattern, track, step, note)
        core.setNote(selectedPattern, track, step, note)
        reconcileRingingVoices()
    }

    /** Cuts any voice whose originating cell no longer holds a note. Aimed at
     * the cell that started it: clearing a later step must not cut a note
     * ringing from an earlier one, and a different pitch retriggers anyway. */
    fun reconcileRingingVoices() {
        for (track in song.tracks.indices) {
            val source = core.ringingSource(track) ?: continue
            val note = song.patterns.getOrNull(source.pattern)?.rows?.getOrNull(track)?.getOrNull(source.step)
                ?: continue
            if (note == Chip.EMPTY_NOTE || note == Chip.NOTE_OFF) core.release(track)
        }
    }

    /** Tap: an empty cell takes the selected note; a filled cell overwrites,
     * or clears if it already matches. */
    fun toggleCell(track: Int, step: Int) {
        checkpoint(coalescing = true, kind = CheckpointKind.Cell)
        if (note(track, step) == selectedNote) {
            setNote(track, step, Chip.EMPTY_NOTE)
        } else {
            setNote(track, step, selectedNote)
            audition(selectedNote, track)
        }
    }

    // MARK: Hardware keyboard

    /** Pulls the cursor back inside the grid. */
    fun clampCursor() {
        selectedTrack = swiftClamp(selectedTrack, 0, maxOf(song.tracks.size - 1, 0))
        selectedStep = swiftClamp(selectedStep, 0, maxOf(patternLength - 1, 0))
    }

    /** Arrow keys: stop at the edges rather than wrapping. Left and Right also
     * ask the grid to follow sideways. */
    fun moveCursor(track: Int = 0, step: Int = 0) {
        hardwareKeyboardInUse = true
        clampCursor()
        selectedTrack = swiftClamp(selectedTrack + track, 0, maxOf(song.tracks.size - 1, 0))
        selectedStep = swiftClamp(selectedStep + step, 0, maxOf(patternLength - 1, 0))
        if (track != 0) update { it.copy(revealRequest = it.revealRequest.bumped(RevealRequest.Reason.CURSOR)) }
    }

    /** Follows a tap, but only once the keyboard is in play. */
    fun placeCursor(track: Int, step: Int) {
        if (!hardwareKeyboardInUse) return
        selectedTrack = track
        selectedStep = step
        clampCursor()
    }

    /** Writes a note at the cursor and steps down, the way a tracker does. */
    fun typeNote(note: Int) {
        hardwareKeyboardInUse = true
        clampCursor()
        if (song.tracks.isEmpty()) return
        // A cell that already holds this note is not an edit.
        if (note(selectedTrack, selectedStep) != note) {
            checkpoint(coalescing = true, kind = CheckpointKind.Note)
            setNote(selectedTrack, selectedStep, note)
        } else {
            pinToSelectedPattern()
        }
        selectedNote = note
        audition(note)
        advanceCursor()
    }

    /** Empties the cell under the cursor and steps down. */
    fun clearAtCursor() {
        hardwareKeyboardInUse = true
        clampCursor()
        if (song.tracks.isEmpty()) return
        if (note(selectedTrack, selectedStep) != Chip.EMPTY_NOTE) {
            checkpoint(coalescing = true, kind = CheckpointKind.Note)
            setNote(selectedTrack, selectedStep, Chip.EMPTY_NOTE)
        } else {
            pinToSelectedPattern()
        }
        advanceCursor()
    }

    /** Wraps, unlike the arrows: typing runs off the end of a pattern. */
    fun advanceCursor() {
        if (patternLength <= 0) return
        selectedStep = (selectedStep + 1) % patternLength
    }

    fun shiftOctave(delta: Int) {
        octave = swiftClamp(octave + delta, OCTAVE_RANGE.first, OCTAVE_RANGE.last)
    }

    /** Arms a note off, or disarms back to the pitch it was armed over. */
    fun toggleNoteOff() {
        selectedNote = if (selectedNote == Chip.NOTE_OFF) lastPitch else Chip.NOTE_OFF
    }

    /** The note a track header's tap demos, or null when there's nothing to
     * play. Muted tracks return null: `audition` would take the voice and lose
     * the record `reconcileRingingVoices` needs. Noise always plays the same
     * hit, and an armed OFF falls back to middle C. */
    fun previewNote(track: Int): Int? {
        val t = song.tracks.getOrNull(track) ?: return null
        if (t.muted) return null
        if (t.kind == ChannelKind.NOISE) return Chip.DEFAULT_PREVIEW_NOTE
        return if (selectedNote >= 0) selectedNote else Chip.DEFAULT_PREVIEW_NOTE
    }

    fun previewTrack(index: Int) {
        val note = previewNote(index) ?: return
        audition(note, index)
    }

    /** Plays the note already in a cell. Writes, arms and moves nothing.
     * Empty and OFF cells are turned away before audio is touched. Returns
     * whether anything was played. */
    fun previewCell(track: Int, step: Int): Boolean {
        val note = note(track, step)
        if (note == Chip.EMPTY_NOTE || note == Chip.NOTE_OFF) return false
        audition(note, track)
        return true
    }

    /** Previews a note on a track, the selected one unless told otherwise. */
    fun audition(note: Int, track: Int? = null) {
        if (!audio.startIfNeeded()) {
            audioError = AudioFailureMessage.start(audio.lastError)
            return
        }
        audioError = null
        core.audition(track ?: selectedTrack, note)
    }

    /** Clears one track in the pattern being edited. */
    fun clearTrack(track: Int) = clearTrack(track, selectedPattern)

    /** Clears one track in one named pattern: a confirmation resolves long
     * after it was raised, and the playhead may have moved the selection. */
    fun clearTrack(track: Int, pattern: Int) {
        if (track !in song.tracks.indices || pattern !in song.patterns.indices) return
        // Already empty: not an edit, so Redo survives.
        if (song.patterns[pattern].rows.getOrNull(track)?.any { it != Chip.EMPTY_NOTE } == true) checkpoint()
        erase(track, pattern)
    }

    private fun erase(track: Int, pattern: Int) {
        if (pattern !in song.patterns.indices || track !in song.tracks.indices) return
        if (pattern == selectedPattern) pinToSelectedPattern()
        song = song.copy(patterns = song.patterns.replacing(pattern) { p ->
            p.copy(rows = p.rows.replacing(track) { Pattern.EMPTY_ROW })
        })
        for (step in 0 until Chip.MAX_STEPS) core.setNote(pattern, track, step, Chip.EMPTY_NOTE)
        reconcileRingingVoices()
    }

    /** Clears every track in the pattern being edited; other patterns stay. */
    fun clearPattern() = clearPattern(selectedPattern)

    /** Clears every track in one pattern without moving the editor to it. */
    fun clearPattern(index: Int) {
        if (index !in song.patterns.indices) return
        if (song.patterns[index].rows.any { row -> row.any { it != Chip.EMPTY_NOTE } }) checkpoint()
        if (index == selectedPattern) pinToSelectedPattern()
        val trackCount = song.tracks.size
        song = song.copy(patterns = song.patterns.replacing(index) { p ->
            p.copy(rows = p.rows.mapIndexed { t, row -> if (t < trackCount) Pattern.EMPTY_ROW else row })
        })
        for (track in 0 until trackCount) {
            for (step in 0 until Chip.MAX_STEPS) core.setNote(index, track, step, Chip.EMPTY_NOTE)
        }
        reconcileRingingVoices()
    }

    // MARK: Parameter sync

    fun pushAll() {
        val s = song.normalized()
        song = s
        selectedPattern = minOf(selectedPattern, s.patterns.size - 1)
        selectedTrack = minOf(selectedTrack, s.tracks.size - 1)
        core.load(s)
        core.focus(selectedPattern)
        core.masterVolume = 0.9
    }

    fun pushTransport() {
        core.tempo = song.tempo
        for ((i, p) in song.patterns.withIndex()) core.setLength(i, p.length)
    }

    fun pushArrangement() {
        core.setChain(song.chain)
    }

    fun pushInstrument(index: Int) {
        val track = song.tracks.getOrNull(index) ?: return
        core.setInstrument(track.instrument, track.kind, index, track.muted)
    }

    // MARK: Patterns

    /** Editing claims a pattern as much as selecting one does. Not called
     * from instrument, tempo or arrangement edits, which aren't pattern-local. */
    private fun pinToSelectedPattern() {
        if (isPlaying && songMode) followsArrangement = false
    }

    fun selectPattern(index: Int) {
        if (index !in song.patterns.indices) return
        // Jumping to the sounding pattern means "back to the song".
        if (isPlaying && songMode) followsArrangement = index == playingPattern
        selectedPattern = index
        core.focus(index)
        clampCursor()
        if (!songMode) playingPattern = index
    }

    fun setPatternLength(length: Int) {
        if (selectedPattern !in song.patterns.indices) return
        checkpoint(coalescing = true, kind = CheckpointKind.PatternLength)
        pinToSelectedPattern()
        val clamped = swiftClamp(length, Chip.patternLengthRange.first, Chip.patternLengthRange.last)
        song = song.copy(patterns = song.patterns.replacing(selectedPattern) { it.copy(length = clamped) })
        core.setLength(selectedPattern, clamped)
        clampCursor()
    }

    /** Adds an empty pattern, appends it to the arrangement, and edits it. */
    fun addPattern(): Int? {
        if (!song.canAddPattern) return null
        checkpoint()
        val new = Pattern(name = song.nextPatternName(), length = pattern.length, trackCount = song.tracks.size)
        song = song.copy(
            patterns = song.patterns + new,
            arrangement = song.arrangement + SongSection(patternID = new.id),
        )
        pushAll()
        pushArrangement()
        selectPattern(song.patterns.size - 1)
        return song.patterns.size - 1
    }

    /** Reads the sequencer's position, or null when nothing follows the
     * arrangement and there is nothing to preserve. */
    private fun soundingPosition(): SoundingPosition? {
        if (!(isPlaying && songMode)) return null
        val sounding = song.patterns.getOrNull(core.currentPattern) ?: return null
        val slot = core.currentChainSlot
        val section = song.sectionIndex(slot) ?: return null
        val start = song.chainStart(section) ?: return null
        return SoundingPosition(
            patternID = sounding.id,
            sectionID = song.arrangement[section].id,
            offset = slot - start,
            followingSectionIDs = song.arrangement.drop(section + 1).map { it.id },
        )
    }

    /** Points the sequencer back at the music it was playing before an edit.
     * Call after pushAll/pushArrangement and before selectPattern. The same
     * section keeps its play-through (clamped into its repeats); a deleted
     * section hands over to the next surviving one, wrapping past the end. */
    private fun restore(position: SoundingPosition?) {
        if (position == null) return
        val chain = song.chain
        var targetSlot: Int? = null
        val section = song.arrangement.indexOfFirst { it.id == position.sectionID }
        val sectionStart = if (section >= 0) song.chainStart(section) else null
        if (sectionStart != null) {
            val repeats = maxOf(song.arrangement[section].repeats, 1)
            targetSlot = sectionStart + minOf(position.offset, repeats - 1)
        } else {
            for (id in position.followingSectionIDs) {
                val next = song.arrangement.indexOfFirst { it.id == id }
                val start = if (next >= 0) song.chainStart(next) else null
                if (start != null) {
                    targetSlot = start
                    break
                }
            }
        }
        var slot = targetSlot ?: 0
        if (slot !in chain.indices) slot = 0
        val pattern = chain[slot]
        if (pattern >= song.patterns.size) return
        core.retarget(slot, pattern)
        playingPattern = pattern
        playingSection = song.sectionIndex(slot) ?: 0
    }

    /** After an edit that moved playback, a following grid goes to what now
     * sounds; a pinned grid stays where the user put it. */
    private fun carryGridToSounding(position: SoundingPosition?) {
        if (position == null || !followsArrangement || playingPattern >= song.patterns.size ||
            selectedPattern == playingPattern
        ) return
        selectedPattern = playingPattern
        core.focus(playingPattern)
        clampCursor()
    }

    /** Copies a pattern's notes into a new one right after it. */
    fun duplicatePattern(index: Int) {
        if (!song.canAddPattern || index !in song.patterns.indices) return
        checkpoint()
        val sounding = soundingPosition()
        val copy = song.patterns[index].copy(id = UUID.randomUUID(), name = song.nextPatternName())
        song = song.copy(
            patterns = song.patterns.toMutableList().apply { add(index + 1, copy) },
            arrangement = song.arrangement + SongSection(patternID = copy.id),
        )
        pushAll()
        pushArrangement()
        restore(sounding)
        selectPattern(index + 1)
    }

    fun removePattern(index: Int) {
        if (song.patterns.size <= 1 || index !in song.patterns.indices) return
        checkpoint()
        val sounding = soundingPosition()
        val id = song.patterns[index].id
        // Follow the pattern being edited, not the slot that was deleted.
        val survivor = if (index < selectedPattern) selectedPattern - 1 else selectedPattern
        val deletesSelection = index == selectedPattern
        song = song.copy(
            patterns = song.patterns.filterIndexed { i, _ -> i != index },
            arrangement = song.arrangement.filter { it.patternID != id },
        )
        pushAll()
        pushArrangement()
        restore(sounding)
        // During SONG playback the grid follows to what sounds now when it was
        // following the deleted sounding pattern, or its pin was deleted.
        val soundingDeleted = sounding?.let { song.patternIndex(it.patternID) == null } ?: false
        if (sounding != null && (deletesSelection || (followsArrangement && soundingDeleted)) &&
            playingPattern < song.patterns.size
        ) {
            selectPattern(playingPattern)
            return
        }
        selectPattern(minOf(survivor, song.patterns.size - 1))
    }

    /** Writes a track's name as it's typed; coalesced per track. */
    fun setTrackName(name: String, index: Int) {
        if (index !in song.tracks.indices) return
        val trimmed = SwiftText.trimWhitespaceAndNewlines(name)
        val accepted = if (trimmed.isEmpty()) null else Graphemes.prefix(name, Track.MAX_NAME_LENGTH)
        // A write that changes nothing is not an edit.
        if (accepted == song.tracks[index].name) return
        checkpoint(coalescing = true, kind = CheckpointKind.TrackName(index))
        song = song.copy(tracks = song.tracks.replacing(index) { it.copy(name = accepted) })
    }

    fun renamePattern(index: Int, name: String) {
        if (index !in song.patterns.indices) return
        val accepted = acceptablePatternName(name, index) ?: return
        if (accepted == song.patterns[index].name) return
        checkpoint()
        song = song.copy(patterns = song.patterns.replacing(index) { it.copy(name = accepted) })
    }

    /** The name a rename would store -- trimmed and truncated -- or null when
     * it's blank or another pattern's. */
    fun acceptablePatternName(name: String, index: Int): String? =
        PatternNameCheck.evaluate(name, song.patterns.map { it.name }, index).acceptedName

    // MARK: Arrangement
    //
    // These renumber the chain the way pattern edits renumber patterns, so
    // each reads the sounding position first and re-aims the core after.

    fun addSection(patternID: UUID) {
        checkpoint()
        val sounding = soundingPosition()
        song = song.copy(arrangement = song.arrangement + SongSection(patternID = patternID))
        pushArrangement()
        restore(sounding)
        carryGridToSounding(sounding)
    }

    /** Removes the sections at [offsets]; an empty arrangement falls back to
     * the first pattern. */
    fun removeSection(offsets: Set<Int>) {
        checkpoint()
        val sounding = soundingPosition()
        var arrangement = song.arrangement.filterIndexed { i, _ -> i !in offsets }
        if (arrangement.isEmpty() && song.patterns.isNotEmpty()) {
            arrangement = listOf(SongSection(patternID = song.patterns[0].id))
        }
        song = song.copy(arrangement = arrangement)
        pushArrangement()
        restore(sounding)
        carryGridToSounding(sounding)
    }

    /** `Array.move(fromOffsets:toOffset:)`: [destination] is an index in the
     * list before the moved sections are taken out. */
    fun moveSection(offsets: Set<Int>, destination: Int) {
        checkpoint()
        val sounding = soundingPosition()
        song = song.copy(arrangement = song.arrangement.moving(offsets, destination))
        pushArrangement()
        restore(sounding)
        carryGridToSounding(sounding)
    }

    /** Replaces a track's whole instrument; a no-op when it already is that preset. */
    fun applyPreset(preset: InstrumentPreset, index: Int) {
        if (index !in song.tracks.indices || song.tracks[index].instrument == preset.instrument) return
        checkpoint()
        song = song.copy(tracks = song.tracks.replacing(index) { it.copy(instrument = preset.instrument) })
        pushInstrument(index)
    }

    fun setSection(id: UUID, patternID: UUID) {
        val i = song.arrangement.indexOfFirst { it.id == id }
        if (i < 0 || song.arrangement[i].patternID == patternID) return
        checkpoint()
        val sounding = soundingPosition()
        song = song.copy(arrangement = song.arrangement.replacing(i) { it.copy(patternID = patternID) })
        pushArrangement()
        restore(sounding)
        carryGridToSounding(sounding)
    }

    fun setSection(id: UUID, repeats: Int) {
        val i = song.arrangement.indexOfFirst { it.id == id }
        if (i < 0) return
        val accepted = swiftClamp(repeats, 1, SongSection.MAX_REPEATS)
        if (accepted == song.arrangement[i].repeats) return
        checkpoint(coalescing = true, kind = CheckpointKind.Repeats(id))
        val sounding = soundingPosition()
        song = song.copy(arrangement = song.arrangement.replacing(i) { it.copy(repeats = accepted) })
        pushArrangement()
        restore(sounding)
        carryGridToSounding(sounding)
    }

    // MARK: Tracks

    /** Appends a track of [kind] and selects it. */
    fun addTrack(kind: ChannelKind) {
        if (!song.canAddTrack) return
        checkpoint()
        song = song.copy(
            tracks = song.tracks + Track(kind = kind),
            patterns = song.patterns.map { it.copy(rows = it.rows + listOf(Pattern.EMPTY_ROW)) },
        )
        pushAll()
        selectedTrack = song.tracks.size - 1
    }

    /** Copies a track's sound and its notes in every pattern. */
    fun duplicateTrack(index: Int) {
        if (!song.canAddTrack || index !in song.tracks.indices) return
        checkpoint()
        val copy = song.tracks[index].copy(id = UUID.randomUUID())
        song = song.copy(
            tracks = song.tracks.toMutableList().apply { add(index + 1, copy) },
            patterns = song.patterns.map { p ->
                val row = p.rows.getOrNull(index) ?: Pattern.EMPTY_ROW
                p.copy(rows = p.rows.toMutableList().apply { add(minOf(index + 1, size), row) })
            },
        )
        pushAll()
        selectedTrack = index + 1
    }

    fun removeTrack(index: Int) {
        if (song.tracks.size <= 1 || index !in song.tracks.indices) return
        checkpoint()
        song = song.copy(
            tracks = song.tracks.filterIndexed { i, _ -> i != index },
            patterns = song.patterns.map { p ->
                if (index < p.rows.size) p.copy(rows = p.rows.filterIndexed { i, _ -> i != index }) else p
            },
        )
        pushAll()
        // After pushAll: load acks any outstanding release. Every voice from
        // index up now belongs to a different track.
        core.releaseAll()
        selectedTrack = minOf(selectedTrack, song.tracks.size - 1)
    }

    /** Moves a track so it ends up at [to] (a final index), taking its row in
     * every pattern with it. The selection follows its track by identity. */
    fun moveTrack(from: Int, to: Int) {
        if (from == to || from !in song.tracks.indices || to !in song.tracks.indices) return
        checkpoint()
        val selectedID = song.tracks.getOrNull(selectedTrack)?.id
        song = song.copy(
            tracks = song.tracks.toMutableList().apply { add(to, removeAt(from)) },
            patterns = song.patterns.map { p ->
                if (from >= p.rows.size) {
                    p
                } else {
                    p.copy(rows = p.rows.toMutableList().apply {
                        val row = removeAt(from)
                        add(minOf(to, size), row)
                    })
                }
            },
        )
        pushAll()
        // Voices are indexed by track; a held note would carry on under
        // whichever track now owns its voice.
        core.releaseAll()
        if (selectedID != null) {
            val moved = song.tracks.indexOfFirst { it.id == selectedID }
            if (moved >= 0) selectedTrack = moved
        }
    }

    /** Switches a track's waveform, keeping its notes; the sound resets to the
     * new kind's default. */
    fun setKind(kind: ChannelKind, index: Int) {
        if (index !in song.tracks.indices || song.tracks[index].kind == kind) return
        checkpoint()
        song = song.copy(tracks = song.tracks.replacing(index) {
            it.copy(kind = kind, instrument = Instrument.defaultFor(kind))
        })
        pushInstrument(index)
    }

    // MARK: Instrument controls
    //
    // iOS does these in the instrument editor's bindings: a coalesced
    // checkpoint of the control's own kind, the write, then pushInstrument.
    // A write that changes nothing is not an edit here either.

    private fun editInstrument(index: Int, kind: CheckpointKind, transform: (Instrument) -> Instrument) {
        val track = song.tracks.getOrNull(index) ?: return
        val updated = transform(track.instrument)
        if (updated == track.instrument) return
        checkpoint(coalescing = true, kind = kind)
        song = song.copy(tracks = song.tracks.replacing(index) { it.copy(instrument = updated) })
        pushInstrument(index)
    }

    fun setVolume(index: Int, value: Double) =
        editInstrument(index, CheckpointKind.Volume(index)) { it.copy(volume = value) }

    fun setDecay(index: Int, value: Double) =
        editInstrument(index, CheckpointKind.Decay(index)) { it.copy(decay = value) }

    fun setSustain(index: Int, value: Boolean) =
        editInstrument(index, CheckpointKind.Sustain(index)) { it.copy(sustain = value) }

    fun setDuty(index: Int, value: Int) =
        editInstrument(index, CheckpointKind.Duty(index)) { it.copy(duty = value) }

    fun setArpeggio(index: Int, value: List<Int>) =
        editInstrument(index, CheckpointKind.Arpeggio(index)) { it.copy(arpeggio = value) }

    /** The track header's speaker: one undo step per tap. */
    fun toggleMute(index: Int) {
        if (index !in song.tracks.indices) return
        checkpoint()
        song = song.copy(tracks = song.tracks.replacing(index) { it.copy(muted = !it.muted) })
        pushInstrument(index)
    }

    // MARK: Song management

    /** Forces the autosave out now (backgrounding, opening another song). */
    fun saveNow(): Boolean {
        autosaveTimer?.cancel()
        autosaveTimer = null
        return save(song)
    }

    private fun scheduleAutosave() {
        if (!autosaveEnabled) return
        autosaveTimer?.cancel()
        autosaveTimer = scheduler.schedule(autosaveInterval) {
            autosaveTimer = null
            save(song)
        }
    }

    private fun resetHistory() {
        history.reset()
        syncHistory()
    }

    fun newSong() {
        stop()
        // Bail before replacing the song if the outgoing save failed, so the
        // failed song stays on screen and storageError names it.
        if (!saveNow()) return
        resetHistory()
        song = Song.create(Song.DEFAULT_NAME)
        selectedPattern = 0
        pushAll()
        saveNow()
    }

    fun open(other: Song) {
        stop()
        if (!saveNow()) return
        // Undo does not reach across songs.
        resetHistory()
        song = other.normalized()
        selectedPattern = 0
        songMode = false
        pushAll()
        core.setSongMode(false)
        saveNow()
    }

    /** Renames a song in the library. The open song is renamed in place, or
     * the next autosave would write the old name back. A name another song
     * already has is refused. */
    fun rename(other: Song, name: String) {
        val trimmed = SwiftText.trimWhitespaces(name)
        if (trimmed.isEmpty()) return
        if (store.loadAll().any { it.id != other.id && it.name == trimmed }) return
        if (other.id == song.id) {
            if (trimmed == song.name) return
            checkpoint()
            song = song.copy(name = trimmed)
            saveNow()
        } else {
            save(other.copy(name = trimmed), makeCurrent = false)
        }
    }

    /** Renames the open song as it's typed: one named run per rename, no
     * trimming until [normalizeSongName]. */
    fun setSongName(name: String) {
        if (name == song.name) return
        checkpoint(run = CheckpointRun.RENAME)
        song = song.copy(name = name)
    }

    /** Ends a title-bar rename: trims, restores the previous name if nothing
     * is left, and closes the run. */
    fun normalizeSongName() {
        try {
            val trimmed = SwiftText.trimWhitespaces(song.name)
            if (trimmed.isEmpty()) {
                // The empty name was rejected, so Redo must not reinstate it.
                if (history.lastRunIs(CheckpointRun.RENAME)) {
                    undo()
                    history.dropRedo()
                    syncHistory()
                }
                return
            }
            if (trimmed != song.name) song = song.copy(name = trimmed)
            saveNow()
        } finally {
            history.endRun()
        }
    }

    fun delete(other: Song) {
        try {
            store.delete(other)
        } catch (e: Exception) {
            // The file is still there, so the song is still real.
            deleteError = DeleteFailureMessage.song(other.name, e)
            return
        }
        // Deleting the song on screen: move off it, or the next autosave
        // writes it straight back.
        if (other.id != song.id) return
        stop()
        autosaveTimer?.cancel()
        autosaveTimer = null
        resetHistory()
        val next = store.loadAll().firstOrNull { it.id != other.id }
        song = next?.normalized() ?: Song.create(Song.DEFAULT_NAME)
        selectedPattern = 0
        songMode = false
        pushAll()
        core.setSongMode(false)
        save(song)
    }

    // MARK: Sharing and import

    /** Writes [other] out as a `.chipsong` and publishes it in [shareFile]. */
    fun share(other: Song) {
        try {
            shareFile = shareWriter.write(other)
            shareError = null
        } catch (e: Exception) {
            shareError = ShareFailureMessage.songFile(other.name, e)
        }
    }

    /** Imports a song from a file and opens it. [source] reads the bytes
     * (a content-resolver stream, say); whatever it throws is reported as a
     * file that couldn't be read, or couldn't be read for permission. */
    fun importSong(source: () -> ByteArray): Boolean {
        val bytes = try {
            source()
        } catch (e: Exception) {
            importError = ImportFailureMessage.file(e)
            return false
        }
        val decoded = try {
            SongDocument.decode(bytes)
        } catch (e: Exception) {
            importError = ImportFailureMessage.file(asNotASong(e))
            return false
        }
        return importDecoded(decoded)
    }

    fun importSong(bytes: ByteArray): Boolean = importSong { bytes }

    /** Imports a song dropped on the library or the editor. */
    fun importDropped(drop: SongDrop): Boolean {
        val song = drop.result.getOrElse { e ->
            importError = ImportFailureMessage.file(asNotASong(e))
            return false
        }
        return importDecoded(song)
    }

    /** Any decode failure means the bytes weren't a song (Swift's `try?`). */
    private fun asNotASong(e: Throwable): Throwable =
        e as? SongDecodeException ?: SongDecodeException("not a song", e)

    /** Adds an already-decoded song to the library and opens it, normalized
     * and with a new identity if its id is already taken. */
    fun importDecoded(incoming: Song): Boolean {
        val normalized = incoming.normalized()
        val existing = store.loadAll().map { it.id }
        val resolved = SongDocument.resolvingCollision(normalized, existing)
        try {
            store.save(resolved, makeCurrent = false)
        } catch (e: Exception) {
            // Named for the song that failed to import; the open one is fine.
            importError = ImportFailureMessage.save(resolved.name, e)
            storageError = null
            return false
        }
        open(resolved)
        importError = null
        return true
    }

    /** Copies a library song without opening it. */
    fun duplicate(other: Song) {
        save(other.copy(id = UUID.randomUUID(), name = other.name + " copy"), makeCurrent = false)
    }

    /** Copies the open song and opens the copy. */
    fun duplicateSong() {
        saveNow()
        open(song.copy(id = UUID.randomUUID(), name = song.name + " copy"))
    }

    // MARK: Export

    /**
     * Renders the WAV or MIDI file on [exportExecutor]. Returns the attempt token, or null
     * when an export is already running. [exportFile] clears at the start so
     * observers see a fresh value when the file lands. Progress and the result
     * come back through [Scheduler.post], bound to the attempt so a late update
     * can't resurrect the bar or overwrite a later export's.
     */
    fun export(options: ExportOptions = exportOptions): Int? {
        if (isExporting) return null
        val attempt = completedExportAttempt + 1
        update { it.copy(isExporting = true, exportFile = null, exportError = null, exportProgress = 0.0) }
        val token = AtomicBoolean(false)
        exportCancel = token
        val song = song
        val renderer = renderer
        val progress: (Double) -> Unit = { fraction ->
            scheduler.post {
                if (isExporting && completedExportAttempt < attempt) update { it.copy(exportProgress = fraction) }
            }
        }
        val job = Runnable {
            val result = try {
                renderer(ExportRequest(song, options, progress) { token.get() })
            } catch (e: Throwable) {
                ExportResult.Failed(e)
            }
            scheduler.post { finishExport(result, attempt, song.name, options.format) }
        }
        try {
            exportExecutor.execute(job)
        } catch (e: RejectedExecutionException) {
            finishExport(ExportResult.Failed(e), attempt, song.name, options.format)
        }
        return attempt
    }

    private fun finishExport(result: ExportResult, attempt: Int, name: String, format: ExportOptions.Format) {
        exportCancel = null
        update {
            val base = it.copy(isExporting = false, exportProgress = 0.0, completedExportAttempt = attempt)
            when (result) {
                is ExportResult.Success -> base.copy(exportFile = result.file)
                // Canceling is not failing; an alert for it would be noise.
                ExportResult.Canceled -> base
                ExportResult.TooLong -> base.copy(exportError = TOO_LONG_MESSAGE)
                is ExportResult.Failed -> base.copy(
                    exportError = WriteFailureMessage.export(name, result.error, format.fileNoun),
                )
            }
        }
    }

    /** Abandons a running export; the renderer notices at its next chunk. */
    fun cancelExport() {
        exportCancel?.set(true)
    }

    companion object {
        /** The octaves the keyboard reaches. */
        val OCTAVE_RANGE: IntRange = 0..8

        const val TOO_LONG_MESSAGE = "Too long for one WAV \u2014 lower the repeat count."

        /** A short riff so the app makes noise the moment it opens. */
        fun seededDemo(): Song {
            val lead = listOf(72, -1, 76, -1, 79, -1, 76, -1, 74, -1, 77, -1, 81, -1, 79, -1)
            val harmony = listOf(-1, 64, -1, 67, -1, 64, -1, 67, -1, 65, -1, 69, -1, 65, -1, 62)
            val bass = listOf(48, -1, -1, -1, 48, -1, -1, -1, 53, -1, -1, -1, 43, -1, -1, -1)
            val drums = listOf(60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, 60, -1)
            val base = Song.create(Song.DEFAULT_NAME).copy(name = "First Loop", tempo = 132.0)
            var pattern = base.patterns[0]
            for ((row, notes) in listOf(lead, harmony, bass, drums).withIndex()) {
                pattern = pattern.copy(rows = pattern.rows.replacing(row) { old ->
                    old.mapIndexed { step, n -> notes.getOrNull(step) ?: n }
                })
            }
            return base.copy(patterns = listOf(pattern))
        }
    }
}

/** This list with element [index] replaced by [transform] of it. */
internal inline fun <T> List<T>.replacing(index: Int, transform: (T) -> T): List<T> =
    mapIndexed { i, item -> if (i == index) transform(item) else item }

/** Swift's `Array.move(fromOffsets:toOffset:)`. */
internal fun <T> List<T>.moving(offsets: Set<Int>, destination: Int): List<T> {
    val valid = offsets.filter { it in indices }.sorted()
    if (valid.isEmpty()) return this
    val moved = valid.map { this[it] }
    val rest = filterIndexed { i, _ -> i !in valid }.toMutableList()
    val insertAt = swiftClamp(destination - valid.count { it < destination }, 0, rest.size)
    rest.addAll(insertAt, moved)
    return rest
}
