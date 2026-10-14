package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import dev.individuation.chiptune.core.model.swiftRounded
import dev.individuation.chiptune.core.store.FileSongStore
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/**
 * Writes a song out as a Standard MIDI File, for taking the notes into a DAW.
 * Port of `Sources/Audio/MidiExport.swift`.
 *
 * Format 1 at 96 ticks per quarter: track 0 is the conductor (name, tempo,
 * meter), then one MIDI track per chip track in song order. The bytes are the
 * iOS writer's for the same song, and the golden files in
 * `Tests/Fixtures/midi-*.mid` hold both to that.
 */
object MidiExport {
    /** 96 divides into a sixteenth evenly, which is all the sequencer can
     * place a note on. */
    const val TICKS_PER_QUARTER = 96
    const val TICKS_PER_STEP = TICKS_PER_QUARTER / Chip.STEPS_PER_BEAT

    /**
     * Writes the file for [request] under [directory].
     *
     * Only the song is used. Repeats and Ending shape a rendered loop; a MIDI
     * file is the arrangement once, and a DAW loops it. There is no progress
     * to report or render to cancel either: the bytes take no time at all.
     */
    fun render(request: ExportRequest, directory: File): ExportResult {
        val target = filename(request.song, directory)
        try {
            // Atomic, so a failed write leaves no half a file behind to be
            // shared, and an old export of the same name stays whole.
            FileSongStore.writeAtomically(target, data(request.song))
        } catch (e: IOException) {
            return ExportResult.Failed(e)
        } catch (e: SecurityException) {
            return ExportResult.Failed(e)
        }
        ExportFiles.pruneStale(target)
        return ExportResult.Success(target)
    }

    /** `<directory>/<SONG-UUID>/<safeName>.mid`, beside the song's WAV. Creates the folder. */
    fun filename(song: Song, directory: File): File = ExportFiles.file(song, directory, "mid")

    /** The file's bytes. Normalizes first, as the WAV export does, so a song
     * straight from a file can't put an out-of-range tempo into the header. */
    fun data(song: Song): ByteArray {
        val normalized = song.normalized()
        val endTick = normalized.arrangementSteps * TICKS_PER_STEP

        val file = ByteArrayOutputStream()
        file.write("MThd".toByteArray(Charsets.US_ASCII))
        file.write(be32(6))
        file.write(be16(1))
        file.write(be16(normalized.tracks.size + 1))
        file.write(be16(TICKS_PER_QUARTER))

        file.write(chunk(conductor(normalized, endTick)))
        val channels = channels(normalized.tracks)
        val audibleDrums = normalized.tracks.any { it.kind == ChannelKind.NOISE && !it.muted }
        for (index in normalized.tracks.indices) {
            file.write(chunk(track(index, normalized, channels[index], audibleDrums, endTick)))
        }
        return file.toByteArray()
    }

    /** GM's drum channel, "channel 10" to a person. */
    const val DRUM_CHANNEL = 9

    /** Melodic tracks count up from channel 0 in song order; every noise track
     * goes to the drum channel. Eight tracks at most, so the count never
     * reaches 9, but it skips it all the same rather than trust that. */
    private fun channels(tracks: List<Track>): List<Int> {
        var next = 0
        return tracks.map { track ->
            if (track.kind == ChannelKind.NOISE) return@map DRUM_CHANNEL
            if (next == DRUM_CHANNEL) next += 1
            next.also { next += 1 }
        }
    }

    /** GM programs, counted from zero: 81 "Lead 1 (square)" for the pulses
     * and 39 "Synth Bass 1" for the triangle, which is where a song's bass
     * lives. Noise is on the drum channel, where a program picks a kit. */
    private fun program(kind: ChannelKind): Int? = when (kind) {
        ChannelKind.PULSE1, ChannelKind.PULSE2 -> 80
        ChannelKind.TRIANGLE -> 38
        ChannelKind.NOISE -> null
    }

    /** GM percussion keys for the noise presets, by preset name. */
    private val PRESET_DRUMS: Map<String, Int> = mapOf(
        "Kick" to 36, "Snare" to 38, "Hat" to 46, "Closed hat" to 42, "Crash" to 49,
    )

    /** The noise preset an instrument still sounds like, for picking its
     * drum. Looser than [InstrumentPreset.matching], which drives the menu's
     * "Custom": volume is how loud the drum is rather than which drum, and the
     * noise channel has no duty cycle, so neither is compared. Decay, hold and
     * arpeggio are the sound itself. */
    private fun drumPreset(instrument: Instrument): InstrumentPreset? =
        InstrumentPreset.presetsFor(ChannelKind.NOISE).firstOrNull {
            it.instrument.decay == instrument.decay &&
                it.instrument.sustain == instrument.sustain &&
                it.instrument.arpeggio == instrument.arpeggio
        }

    /**
     * Which drum each note on a noise track plays.
     *
     * A track that still sounds like a preset plays that preset's drum for
     * every note, whatever pitch it was written at and however loud it is. A custom one is spread over kick,
     * snare and closed hat by where each note sits among the track's own
     * distinct notes, lowest to highest. It has to be relative: the library
     * songs write their noise between 52 and 71, so fixed pitch ranges would
     * make nearly everything a snare. Only the notes the arrangement plays
     * count, so an unplayed pattern can't move the bands.
     */
    private fun drumMap(index: Int, song: Song): (Int) -> Int {
        val instrument = song.tracks[index].instrument
        drumPreset(instrument)?.let { preset ->
            PRESET_DRUMS[preset.name]?.let { drum -> return { drum } }
        }
        val distinct = song.chain.flatMap { song.patterns[it].rows[index].take(song.patterns[it].length) }
            .filter { it >= 0 }.toSortedSet().toList()
        val bands = listOf(36, 38, 42)
        val drums = HashMap<Int, Int>()
        for ((i, note) in distinct.withIndex()) {
            // A lone note takes the middle band, a snare, not the bottom one.
            drums[note] = if (distinct.size == 1) 38 else bands[i * 3 / distinct.size]
        }
        // Every note the track plays was counted above; the fallback is
        // only there so a lookup can't fail.
        return { drums[it] ?: 38 }
    }

    /** The longest a drum hit is held. GM drums are one-shots, so the length
     * only matters for one thing: every noise track shares the drum channel,
     * and an off landing on the tick where another track starts the same
     * drum leaves the result to however a DAW orders the merge. A tick short
     * of a step can never meet another note's on. */
    private const val MAX_DRUM_TICKS = TICKS_PER_STEP - 1

    /** One chip track's MIDI track. [audibleDrums] says whether any noise
     * track in the song is unmuted, which decides how a muted noise track can
     * be silenced. */
    private fun track(index: Int, song: Song, channel: Int, audibleDrums: Boolean, endTick: Int): TrackEvents {
        val track = song.tracks[index]
        val instrument = track.instrument
        val isDrum = track.kind == ChannelKind.NOISE
        val pitch: (Int) -> Int = if (isDrum) drumMap(index, song) else { note -> note }

        // A muted track is written in full, so unmuting it in a DAW brings
        // the part back, but silenced with its channel's volume. A muted noise
        // track can't do that when an audible one shares the drum channel, so
        // it goes as quiet as a note can instead.
        val silenceChannel = track.muted && !(isDrum && audibleDrums)
        val quietNotes = track.muted && !silenceChannel

        // Volume goes into the velocity rather than a CC7, because the noise
        // tracks share one channel and one channel has one volume. Never 0,
        // which a note-on would read as a note-off.
        val velocity = if (quietNotes) 1 else maxOf(1, swiftRounded(instrument.volume * 127).toInt())
        // How long a decaying note is heard, in ticks. `decay` is the time to
        // -60 dB, which is where the synth's own envelope gives out.
        val decayTicks = maxOf(1, swiftRounded(instrument.decay * song.tempo / 60 * TICKS_PER_QUARTER.toDouble()).toInt())

        val events = TrackEvents()
        val label = song.fullLabel(index)
        events.append(0, text(0x03, if (track.muted) "$label (muted)" else label))
        program(track.kind)?.let { events.append(0, 0xC0 or channel, it) }
        if (silenceChannel) events.append(0, 0xB0 or channel, 0x07, 0x00)

        // The note still sounding, and the tick its decay would end it by.
        var soundingNote = -1
        var soundingEndsBy = 0
        fun release(tick: Int) {
            if (soundingNote < 0) return
            // A decayed note was already silent before whatever ends it now;
            // its off goes where the sound stopped. Writing it late here keeps
            // the list in order, since that tick is past the note's own on.
            // Release velocity 64 is the spec's "no release velocity" value.
            events.append(minOf(soundingEndsBy, tick), 0x80 or channel, soundingNote, 0x40)
            soundingNote = -1
        }

        // `chain` is exactly what playback walks, repeats expanded and capped,
        // so a held note carries over a pattern boundary just as
        // `ChipCore.triggerStep` lets it.
        var tick = 0
        for (patternIndex in song.chain) {
            val pattern = song.patterns[patternIndex]
            for (step in 0 until pattern.length) {
                val cell = pattern.rows[index][step]
                if (cell == Chip.NOTE_OFF) {
                    release(tick)
                } else if (cell >= 0) {
                    // Off before on, so a repeated pitch retriggers instead of
                    // being started and then ended at the same instant.
                    release(tick)
                    val note = pitch(cell)
                    events.append(tick, 0x90 or channel, note, velocity)
                    soundingNote = note
                    soundingEndsBy = if (instrument.sustain) Int.MAX_VALUE else tick + decayTicks
                    if (isDrum) soundingEndsBy = minOf(soundingEndsBy, tick + MAX_DRUM_TICKS)
                }
                tick += TICKS_PER_STEP
            }
        }
        release(endTick)
        // Every track ends on the last tick, sounding or not, so the file
        // loops at the arrangement's length in a DAW.
        events.append(endTick, 0xFF, 0x2F, 0x00)
        return events
    }

    private fun conductor(song: Song, endTick: Int): TrackEvents {
        val events = TrackEvents()
        events.append(0, text(0x03, song.name))
        val micros = swiftRounded(60_000_000.0 / song.tempo).toInt()
        events.append(0, 0xFF, 0x51, 0x03, micros shr 16 and 0xFF, micros shr 8 and 0xFF, micros and 0xFF)
        // 4/4; a click every 24 MIDI clocks (one quarter); eight 32nds to the
        // quarter. The app has no meter of its own, and four sixteenths to the
        // beat reads naturally as 4/4.
        events.append(0, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08)
        events.append(endTick, 0xFF, 0x2F, 0x00)
        return events
    }

    // MARK: Bytes

    /** A track's events at absolute ticks, appended in the order they are to
     * be written. Deltas are worked out on the way to bytes, so a caller
     * never has to. */
    private class TrackEvents {
        val items = ArrayList<Pair<Int, ByteArray>>()

        fun append(tick: Int, bytes: ByteArray) {
            items.add(tick to bytes)
        }

        fun append(tick: Int, vararg bytes: Int) = append(tick, ByteArray(bytes.size) { bytes[it].toByte() })
    }

    private fun chunk(events: TrackEvents): ByteArray {
        val body = ByteArrayOutputStream()
        var last = 0
        for ((tick, bytes) in events.items) {
            body.write(vlq(tick - last))
            body.write(bytes)
            last = tick
        }
        val out = ByteArrayOutputStream()
        out.write("MTrk".toByteArray(Charsets.US_ASCII))
        out.write(be32(body.size()))
        body.writeTo(out)
        return out.toByteArray()
    }

    /** A text meta event. The length is the UTF-8 byte count, not the
     * character count: one non-ASCII letter in a name would otherwise cut
     * the end off it, or swallow the next event's first byte. */
    private fun text(type: Int, string: String): ByteArray {
        val bytes = string.toByteArray(Charsets.UTF_8)
        return byteArrayOf(0xFF.toByte(), type.toByte()) + vlq(bytes.size) + bytes
    }

    private fun vlq(value: Int): ByteArray {
        val out = ArrayDeque<Byte>()
        out.addFirst((value and 0x7F).toByte())
        var rest = value shr 7
        while (rest > 0) {
            out.addFirst((rest and 0x7F or 0x80).toByte())
            rest = rest shr 7
        }
        return out.toByteArray()
    }

    private fun be16(value: Int): ByteArray =
        byteArrayOf((value shr 8 and 0xFF).toByte(), (value and 0xFF).toByte())

    private fun be32(value: Int): ByteArray = byteArrayOf(
        (value shr 24 and 0xFF).toByte(), (value shr 16 and 0xFF).toByte(),
        (value shr 8 and 0xFF).toByte(), (value and 0xFF).toByte(),
    )
}
