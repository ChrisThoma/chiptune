package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import java.io.File
import java.util.UUID

/** A request for the grid to bring the selected track's column on screen.
 * Counted rather than flagged: two presses are two requests. */
data class RevealRequest(val generation: Int = 0, val reason: Reason = Reason.UNDO_REDO) {
    enum class Reason {
        /** A snapshot was restored; reveal only if it moved the selection, centred. */
        UNDO_REDO,

        /** Left or Right; scroll just far enough, like a text caret. */
        CURSOR,
    }

    fun bumped(reason: Reason): RevealRequest = RevealRequest(generation + 1, reason)
}

/** Tags a coalescing checkpoint with the operation that made it, so only
 * edits of the same kind fold into one undo step. */
sealed interface CheckpointKind {
    data object Tempo : CheckpointKind
    data object Cell : CheckpointKind
    data object Note : CheckpointKind
    data object PatternLength : CheckpointKind
    data class TrackName(val track: Int) : CheckpointKind
    data class Volume(val track: Int) : CheckpointKind
    data class Sustain(val track: Int) : CheckpointKind
    data class Decay(val track: Int) : CheckpointKind
    data class Duty(val track: Int) : CheckpointKind
    data class Arpeggio(val track: Int) : CheckpointKind
    data class Repeats(val section: UUID) : CheckpointKind
}

/** A named run of edits that is one undo step however long it takes. */
enum class CheckpointRun { RENAME }

/**
 * Everything the UI reads from a [Studio], as one immutable value. Every
 * Studio mutation replaces it atomically in `Studio.state`, so Compose can
 * `collectAsState()` once and read fields off it.
 */
data class StudioState(
    val song: Song,
    /** Note the keyboard writes into the grid; [Chip.NOTE_OFF] when OFF is armed. */
    val selectedNote: Int = 60,
    /** Index into `song.tracks`. */
    val selectedTrack: Int = 0,
    /** Step the hardware-keyboard cursor sits on. */
    val selectedStep: Int = 0,
    /** Octave the keys write in (C4 = 60 at octave 5), 0...8. */
    val octave: Int = 5,
    /** A hardware key has been pressed; until then the grid draws no cursor. */
    val hardwareKeyboardInUse: Boolean = false,
    /** Bumped by each Escape / Ctrl+. with something presented. */
    val dismissRequests: Int = 0,
    val revealRequest: RevealRequest = RevealRequest(),
    /** Index into `song.patterns`: the pattern the grid is editing. */
    val selectedPattern: Int = 0,
    /** PATT loops the pattern being edited; SONG follows the arrangement. */
    val songMode: Boolean = false,
    val isPlaying: Boolean = false,
    /** Step the sequencer is on, for the playhead highlight. */
    val playhead: Int = 0,
    /** Pattern the sequencer is on; in SONG mode not always the edited one. */
    val playingPattern: Int = 0,
    /** Arrangement section sounding in SONG mode. */
    val playingSection: Int = 0,
    val canUndo: Boolean = false,
    val canRedo: Boolean = false,
    /** What the Export sheet last asked for: WAV or MIDI, repeats and ending.
     * Held here, not in the sheet, so it survives the sheet closing. */
    val exportOptions: ExportOptions = ExportOptions(),
    /** The finished WAV or MIDI file, set when an export succeeds. */
    val exportFile: File? = null,
    val isExporting: Boolean = false,
    /** 0...1 while [isExporting]. */
    val exportProgress: Double = 0.0,
    /** Monotonic: bumped as each export finishes, whatever its outcome. */
    val completedExportAttempt: Int = 0,
    /** Export failed (null when canceled: canceling is not failing). */
    val exportError: String? = null,
    /** Audio wouldn't start. */
    val audioError: String? = null,
    /** A save failed: the one that loses work. */
    val storageError: String? = null,
    /** A library delete failed. */
    val deleteError: String? = null,
    /** Song files that would not decode, reported once per file. */
    val unreadableSongsNotice: String? = null,
    /** Import failed. */
    val importError: String? = null,
    /** Preparing a song to share failed. */
    val shareError: String? = null,
    /** A `.chipsong` written out and waiting for a share sheet. */
    val shareFile: File? = null,
    /** Dialogs and sheets holding state read from the current song. */
    val songBoundPresenters: SongBoundPresenters = SongBoundPresenters(),
) {
    /** The keyboard is about to write a note off rather than a pitch. */
    val noteOffArmed: Boolean get() = selectedNote == Chip.NOTE_OFF

    /** The pattern the grid is editing. */
    val pattern: Pattern get() = song.patterns.getOrNull(selectedPattern) ?: song.patterns[0]

    /** Steps shown in the grid. */
    val patternLength: Int get() = pattern.length

    /** Kind of the track the keyboard writes to. */
    val selectedKind: ChannelKind get() = song.tracks.getOrNull(selectedTrack)?.kind ?: ChannelKind.PULSE1
}
