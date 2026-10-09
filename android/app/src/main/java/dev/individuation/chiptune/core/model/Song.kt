package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.text.Graphemes
import dev.individuation.chiptune.core.text.SwiftText
import java.util.UUID

/** Port of the model in `Sources/Model/Song.swift`. Everything here is an
 * immutable value; edits go through `copy` (Studio snapshots these for undo). */

enum class ChannelKind(val rawValue: Int, val shortName: String, val fullName: String) {
    PULSE1(0, "PU1", "Pulse 1"),
    PULSE2(1, "PU2", "Pulse 2"),
    TRIANGLE(2, "TRI", "Triangle"),
    NOISE(3, "NOI", "Noise"),
    ;

    /** Only the pulse channels have a meaningful duty cycle. */
    val hasDuty: Boolean get() = this == PULSE1 || this == PULSE2

    companion object {
        fun fromRaw(raw: Int): ChannelKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** Per-channel voice settings. */
data class Instrument(
    /** Index into [DUTY_CYCLES]. */
    val duty: Int = 2,
    /** 0…1 channel level. */
    val volume: Double = 0.8,
    /** Seconds for the amplitude envelope to fall to silence. */
    val decay: Double = 0.35,
    /** Holds the note at full level until the next one or an OFF. */
    val sustain: Boolean = false,
    /** Semitone offsets cycled at ~60 Hz. Empty means no arpeggio. */
    val arpeggio: List<Int> = emptyList(),
) {
    /** Forces every field back into the range the synth can actually play. */
    fun normalized(): Instrument = copy(
        duty = swiftClamp(duty, 0, DUTY_CYCLES.size - 1),
        volume = if (volume.isFinite()) swiftClamp(volume, 0.0, 1.0) else 0.8,
        decay = if (decay.isFinite()) swiftClamp(decay, 0.01, 4.0) else 0.35,
        arpeggio = arpeggio.take(MAX_ARPEGGIO_STEPS)
            .map { swiftClamp(it, -MAX_ARPEGGIO_SEMITONES, MAX_ARPEGGIO_SEMITONES) },
    )

    companion object {
        val DUTY_CYCLES: List<Double> = listOf(0.125, 0.25, 0.5, 0.75)
        val DUTY_LABELS: List<String> = listOf("12%", "25%", "50%", "75%")

        /** Files written before hold was a switch say hold with a decay this long. */
        const val LEGACY_HOLD_DECAY = 3.99

        /** Widest arpeggio offset a file may declare, in semitones. */
        const val MAX_ARPEGGIO_SEMITONES = 48
        /** The core reads at most this many offsets. */
        const val MAX_ARPEGGIO_STEPS = 4

        /** The first preset of the kind. */
        fun defaultFor(kind: ChannelKind): Instrument =
            InstrumentPreset.presetsFor(kind).firstOrNull()?.instrument ?: Instrument(duty = 2, volume = 0.8, decay = 0.35)
    }
}

data class Track(
    /** Stable across insertion and deletion. */
    val id: UUID = UUID.randomUUID(),
    val kind: ChannelKind,
    val instrument: Instrument = Instrument.defaultFor(kind),
    val muted: Boolean = false,
    /** Overrides the channel code wherever a label is drawn; null rather than "". */
    val name: String? = null,
) {
    /** A name from a file can be any string: blank becomes null, long is capped. */
    fun normalizedName(): Track {
        val trimmed = name?.let { SwiftText.trimWhitespaceAndNewlines(it) }
        if (trimmed.isNullOrEmpty()) return if (name == null) this else copy(name = null)
        return copy(name = Graphemes.prefix(trimmed, MAX_NAME_LENGTH))
    }

    companion object {
        /** Long enough for "Harmony", short enough for a column header. */
        const val MAX_NAME_LENGTH = 16
    }
}

/** A block of steps — one row per track. */
data class Pattern(
    val id: UUID = UUID.randomUUID(),
    /** Short display name, "A" through "P" by default. */
    val name: String = "A",
    /** Steps in this pattern, 4…64. */
    val length: Int = 16,
    /** One row per track, each [Chip.MAX_STEPS] long; [Chip.EMPTY_NOTE] for a rest. */
    val rows: List<List<Int>> = emptyList(),
) {
    constructor(name: String, length: Int = 16, trackCount: Int) :
        this(UUID.randomUUID(), name, length, List(maxOf(trackCount, 1)) { EMPTY_ROW })

    val isEmpty: Boolean get() = rows.all { row -> row.all { it == Chip.EMPTY_NOTE } }

    /** A pitch at a step the sequencer reaches; rests and note-offs don't count. */
    val hasNotes: Boolean get() = rows.any { rowHasNotes(it) }

    fun rowHasNotes(row: List<Int>): Boolean = row.take(maxOf(length, 0)).any { it in 0..127 }

    /** This pattern with one cell changed. */
    fun withNote(row: Int, step: Int, note: Int): Pattern =
        copy(rows = rows.mapIndexed { r, cells ->
            if (r != row) cells else cells.mapIndexed { s, n -> if (s == step) note else n }
        })

    /** Pads or trims rows so a corrupt file can't send the audio thread past its buffers. */
    fun normalized(trackCount: Int): Pattern {
        val want = maxOf(trackCount, 1)
        val sized = when {
            rows.size < want -> rows + List(want - rows.size) { EMPTY_ROW }
            rows.size > want -> rows.take(want)
            else -> rows
        }
        val cleaned = sized.map { row ->
            val fitted = when {
                row.size < Chip.MAX_STEPS -> row + List(Chip.MAX_STEPS - row.size) { Chip.EMPTY_NOTE }
                row.size > Chip.MAX_STEPS -> row.take(Chip.MAX_STEPS)
                else -> row
            }
            fitted.map { n -> if (n != Chip.EMPTY_NOTE && n != Chip.NOTE_OFF && n !in 0..127) Chip.EMPTY_NOTE else n }
        }
        return copy(length = swiftClamp(length, Chip.patternLengthRange.first, Chip.patternLengthRange.last), rows = cleaned)
    }

    companion object {
        val EMPTY_ROW: List<Int> = List(Chip.MAX_STEPS) { Chip.EMPTY_NOTE }
    }
}

/** One entry in the arrangement: play this pattern this many times. */
data class SongSection(
    val id: UUID = UUID.randomUUID(),
    val patternID: UUID,
    val repeats: Int = 1,
) {
    companion object {
        const val MAX_REPEATS = 16
    }
}

data class Song(
    val id: UUID = UUID.randomUUID(),
    val name: String = DEFAULT_NAME,
    val tempo: Double = 120.0,
    val tracks: List<Track>,
    val patterns: List<Pattern>,
    /** Play order. Never empty once normalized. */
    val arrangement: List<SongSection>,
    /** Seconds since 2001-01-01 ([SongClock]). */
    val modified: Double = SongClock.now(),
) {
    companion object {
        /** What a new song, or one whose stored name is blank, is called. */
        const val DEFAULT_NAME = "Untitled"

        /** Swift's `Song(name:)`: one track per channel kind, pattern A, played once. */
        fun create(name: String = DEFAULT_NAME): Song {
            val tracks = ChannelKind.entries.map { Track(kind = it) }
            val pattern = Pattern(name = "A", length = 16, trackCount = tracks.size)
            return Song(name = name, tracks = tracks, patterns = listOf(pattern),
                arrangement = listOf(SongSection(patternID = pattern.id)))
        }

        /** "A" for 0, "B" for 1… */
        fun letter(index: Int): String = ('A' + minOf(index, 25)).toString()

        private fun usableName(name: String?): String? =
            name?.let { SwiftText.trimWhitespaceAndNewlines(it) }?.takeIf { it.isNotEmpty() }
    }

    // MARK: Invariants

    fun normalized(): Song {
        val trimmedName = SwiftText.trimWhitespaceAndNewlines(name)
        val newName = trimmedName.ifEmpty { DEFAULT_NAME }
        val newTempo = if (tempo.isFinite()) swiftClamp(tempo, Chip.TEMPO_MIN, Chip.TEMPO_MAX) else 120.0

        var newTracks = if (tracks.isEmpty()) ChannelKind.entries.map { Track(kind = it) } else tracks
        if (newTracks.size > Chip.MAX_TRACKS) newTracks = newTracks.take(Chip.MAX_TRACKS)
        newTracks = newTracks.map { it.copy(instrument = it.instrument.normalized()).normalizedName() }
        val seenTracks = HashSet<UUID>()
        newTracks = newTracks.map { if (seenTracks.add(it.id)) it else it.copy(id = UUID.randomUUID()) }

        var newPatterns = patterns.ifEmpty { listOf(Pattern(name = "A", length = 16, trackCount = newTracks.size)) }
        if (newPatterns.size > Chip.MAX_PATTERNS) newPatterns = newPatterns.take(Chip.MAX_PATTERNS)
        newPatterns = normalizePatternNames(newPatterns.map { it.normalized(newTracks.size) })
        val seenPatterns = HashSet<UUID>()
        newPatterns = newPatterns.map { if (seenPatterns.add(it.id)) it else it.copy(id = UUID.randomUUID()) }

        val known = newPatterns.map { it.id }.toHashSet()
        var newArrangement = arrangement.filter { it.patternID in known }
            .map { it.copy(repeats = swiftClamp(it.repeats, 1, SongSection.MAX_REPEATS)) }
        if (newArrangement.isEmpty()) newArrangement = listOf(SongSection(patternID = newPatterns[0].id))
        val seenSections = HashSet<UUID>()
        newArrangement = newArrangement.map { if (seenSections.add(it.id)) it else it.copy(id = UUID.randomUUID()) }

        return copy(name = newName, tempo = newTempo, tracks = newTracks, patterns = newPatterns, arrangement = newArrangement)
    }

    // MARK: Patterns

    val canAddPattern: Boolean get() = patterns.size < Chip.MAX_PATTERNS

    fun patternIndex(id: UUID): Int? = patterns.indexOfFirst { it.id == id }.takeIf { it >= 0 }

    /** Holds pattern names to what the pattern bar enforces: trimmed, at most
     * [PatternNameCheck.MAX_LENGTH] characters, not blank, unique. The first
     * holder of a name keeps it; a blank or repeated one takes the first
     * unused letter. */
    private fun normalizePatternNames(list: List<Pattern>): List<Pattern> {
        val limit = PatternNameCheck.MAX_LENGTH
        val kept = HashSet<String>()
        val names = list.map { it.name }.toMutableList()
        val needsName = ArrayList<Int>()
        for (i in list.indices) {
            val trimmed = SwiftText.trimWhitespaceAndNewlines(list[i].name)
            val clipped = SwiftText.trimWhitespaceAndNewlines(NameCap.clip(trimmed, limit))
            if (clipped.isNotEmpty() && kept.add(clipped)) names[i] = clipped else needsName.add(i)
        }
        var next = 0
        for (i in needsName) {
            var candidate = letter(next)
            while (candidate in kept && next < 25) {
                next += 1
                candidate = letter(next)
            }
            if (candidate in kept) candidate = list[i].id.toString().uppercase().take(limit)
            kept.add(candidate)
            names[i] = candidate
        }
        return list.mapIndexed { i, p -> if (p.name == names[i]) p else p.copy(name = names[i]) }
    }

    /** First unused letter, so deleting B and adding again gives you B back. */
    fun nextPatternName(): String {
        val taken = patterns.map { it.name }.toSet()
        for (i in 0 until Chip.MAX_PATTERNS) {
            val name = letter(i)
            if (name !in taken) return name
        }
        return "${patterns.size + 1}"
    }

    /** This song with one cell of one pattern changed. */
    fun withNote(pattern: Int, row: Int, step: Int, note: Int): Song =
        copy(patterns = patterns.mapIndexed { i, p -> if (i == pattern) p.withNote(row, step, note) else p })

    // MARK: Arrangement

    /** The arrangement flattened into pattern indices — what the audio thread walks. */
    val chain: List<Int>
        get() {
            val out = ArrayList<Int>()
            for (section in arrangement) {
                val index = patternIndex(section.patternID) ?: continue
                repeat(maxOf(section.repeats, 1)) { if (out.size < Chip.MAX_CHAIN) out.add(index) }
            }
            return out.ifEmpty { listOf(0) }
        }

    /** Which arrangement section a flattened chain slot belongs to. */
    fun sectionIndex(chainSlot: Int): Int? {
        if (chainSlot < 0) return null
        var remaining = chainSlot
        for ((index, section) in arrangement.withIndex()) {
            if (patternIndex(section.patternID) == null) continue
            val plays = maxOf(section.repeats, 1)
            if (remaining < plays) return index
            remaining -= plays
        }
        return null
    }

    /** The first chain slot a section occupies, or null when it plays nothing. */
    fun chainStart(ofSection: Int): Int? {
        if (ofSection < 0 || ofSection >= arrangement.size || patternIndex(arrangement[ofSection].patternID) == null) return null
        var slot = 0
        for ((i, section) in arrangement.withIndex()) {
            if (i == ofSection) return slot
            if (patternIndex(section.patternID) == null) continue
            slot += maxOf(section.repeats, 1)
        }
        return null
    }

    /** The full expansion before the [Chip.MAX_CHAIN] cap. */
    val plannedPlaythroughs: Int
        get() = arrangement.sumOf { if (patternIndex(it.patternID) != null) maxOf(it.repeats, 1) else 0 }

    val exceedsChainCapacity: Boolean get() = plannedPlaythroughs > Chip.MAX_CHAIN

    /** Steps in one pass of the whole arrangement. */
    val arrangementSteps: Int get() = chain.sumOf { patterns.getOrNull(it)?.length ?: 0 }

    /** Seconds for one pass of the arrangement, at the current tempo. */
    val arrangementDuration: Double
        get() = arrangementSteps.toDouble() * 60.0 / (maxOf(tempo, 1.0) * Chip.STEPS_PER_BEAT.toDouble())

    // MARK: Export

    /** A note in a pattern the arrangement plays (muted tracks count). */
    val hasNotes: Boolean get() = chain.toSet().any { patterns.getOrNull(it)?.hasNotes ?: false }

    /** A note in any pattern, arranged or not. */
    val hasNotesAnywhere: Boolean get() = patterns.any { it.hasNotes }

    /** A note the arrangement plays on a track that isn't muted. */
    val hasAudibleNotes: Boolean
        get() {
            val reachable = chain.toSet()
            return tracks.withIndex().any { (index, track) ->
                !track.muted && reachable.any { p ->
                    val pattern = patterns.getOrNull(p)
                    val row = pattern?.rows?.getOrNull(index)
                    pattern != null && row != null && pattern.rowHasNotes(row)
                }
            }
        }

    /** Longest decay among tracks heard ringing out, or null. */
    val maxAudibleDecay: Double?
        get() {
            val reachable = chain.toSet()
            var longest: Double? = null
            for ((index, track) in tracks.withIndex()) {
                if (track.muted || track.instrument.sustain) continue
                val plays = patterns.indices.any { p ->
                    if (p !in reachable) return@any false
                    val pattern = patterns[p]
                    val row = pattern.rows.getOrNull(index)
                    track.instrument.decay > 0 && row != null && pattern.rowHasNotes(row)
                }
                if (!plays) continue
                longest = maxOf(longest ?: 0.0, track.instrument.decay)
            }
            return longest
        }

    // MARK: Track labels

    val canAddTrack: Boolean get() = tracks.size < Chip.MAX_TRACKS

    /** One track has nowhere to go, so reorder mode does nothing. */
    val canReorderTracks: Boolean get() = tracks.size > 1

    /** Short column name: "TRI", or "TRI A" / "TRI B" for duplicated kinds. */
    fun label(index: Int): String {
        val track = tracks.getOrNull(index) ?: return ""
        usableName(track.name)?.let { return it }
        val suffix = duplicateSuffix(index) ?: return track.kind.shortName
        return "${track.kind.shortName} $suffix"
    }

    /** Spoken/title name — "Triangle B". */
    fun fullLabel(index: Int): String {
        val track = tracks.getOrNull(index) ?: return ""
        usableName(track.name)?.let { return it }
        val suffix = duplicateSuffix(index) ?: return track.kind.fullName
        return "${track.kind.fullName} $suffix"
    }

    private fun duplicateSuffix(index: Int): String? {
        val track = tracks.getOrNull(index) ?: return null
        val sameKind = tracks.indices.filter { tracks[it].kind == track.kind }
        if (sameKind.size <= 1) return null
        val position = sameKind.indexOf(index)
        return if (position < 0) null else letter(position)
    }
}

object NoteName {
    val NAMES: List<String> = listOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")

    /** MIDI note number → "C#4"; a note-off is "REST", a rest is "". */
    fun label(midi: Int): String {
        if (midi == Chip.NOTE_OFF) return "REST"
        if (midi < 0) return ""
        return "${NAMES[midi % 12]}${midi / 12 - 1}"
    }

    fun frequency(midi: Int): Double = 440.0 * StrictMath.pow(2.0, (midi.toDouble() - 69.0) / 12.0)
}
