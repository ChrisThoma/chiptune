package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.model.swiftRounded
import java.io.File
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of `ExportOptionsTests.swift` (the `WavExport` half; the Studio half
 * arrives with Studio in Phase 3): loop count, tail mode, progress and
 * cancellation. Durations are asserted against the tempo and step count. */
class ExportOptionsTest {

    @get:Rule val temp = TemporaryFolder()

    private val sampleRate = 44100.0

    /** 4 steps at 240 BPM = 0.25 s a pass. Sustaining, so there is something to ring out. */
    private fun makeSong(name: String = "Options"): Song =
        TestSongs.empty(name = name, tempo = 240.0, length = 4)
            .withInstrument(0) { it.copy(sustain = true, volume = 0.9) }
            .setNote(0, 0, 60).setNote(0, 2, 67)

    private fun onePassSamples(song: Song): Int =
        swiftRounded(sampleRate * 60.0 / (song.tempo * 4.0)).toInt() * song.arrangementSteps

    private fun render(song: Song, options: ExportOptions): File {
        val result = WavExport.render(ExportRequest(song, options), temp.root)
        if (result !is ExportResult.Success) fail("export did not succeed: $result")
        return (result as ExportResult.Success).file
    }

    private fun samples(file: File): FloatArray = WavFile.samples(file)

    // MARK: Length

    @Test fun seamlessLoopIsExactlyTheRequestedNumberOfPasses() {
        val song = makeSong()
        val pass = onePassSamples(song)
        for (count in listOf(1, 2, 5)) {
            assertEquals("$count repeats should be exactly $count passes long",
                pass * count, samples(render(song, ExportOptions(count, ExportOptions.TailMode.SEAMLESS_LOOP))).size)
        }
    }

    @Test fun ringOutAddsTheTailToTheEnd() {
        val song = makeSong()
        val pass = onePassSamples(song)
        val tail = (sampleRate * WavExport.tailSeconds(song)).toInt()
        assertEquals(44100, tail)
        for (count in listOf(1, 3)) {
            assertEquals(pass * count + tail, samples(render(song, ExportOptions(count, ExportOptions.TailMode.RING_OUT))).size)
        }
    }

    @Test fun ringOutTailScalesWithDecayAndEndsInTrueSilence() {
        val song = TestSongs.empty(name = "LongDecay", tempo = 240.0, length = 4)
            .withInstrument(0) { it.copy(sustain = false, decay = 4.0, volume = 0.9) }
            .setNote(0, 3, 60)
        val pass = onePassSamples(song)
        val audio = samples(render(song, ExportOptions(1, ExportOptions.TailMode.RING_OUT)))
        assertEquals("decay 4.0 should push the tail to its 6 s ceiling", pass + (sampleRate * 6.0).toInt(), audio.size)
        val from = audio.size - (sampleRate * 0.25).toInt()
        for (i in from until audio.size) assertEquals("expected exact digital silence at the end (sample $i)", 0f, audio[i])
    }

    @Test fun tailSecondsFormula() {
        fun song(transform: (Song) -> Song): Song = transform(TestSongs.empty(length = 4))

        val short = song { it.withInstrument(0) { i -> i.copy(sustain = false, decay = 0.2) }.setNote(0, 0, 60) }
        assertEquals("short decays keep the 1 s floor", 1.0, WavExport.tailSeconds(short), 0.0)

        val scaling = song { it.withInstrument(0) { i -> i.copy(sustain = false, decay = 2.0) }.setNote(0, 0, 60) }
        assertEquals("decay 2.0 -> tail 3.0", 3.0, WavExport.tailSeconds(scaling), 0.0)

        val ceiling = song { it.withInstrument(0) { i -> i.copy(sustain = false, decay = 4.0) }.setNote(0, 0, 60) }
        assertEquals("decay 4.0 -> the 6 s ceiling", 6.0, WavExport.tailSeconds(ceiling), 0.0)

        val sustaining = song { it.withInstrument(0) { i -> i.copy(sustain = true, decay = 4.0) }.setNote(0, 0, 60) }
        assertEquals("a sustaining track releases fast, not counted", 1.0, WavExport.tailSeconds(sustaining), 0.0)

        val muted = song {
            it.withInstrument(0) { i -> i.copy(sustain = false, decay = 4.0) }.withTrack(0) { t -> t.copy(muted = true) }
                .setNote(0, 0, 60)
        }
        assertEquals("a muted track can't be heard ringing out", 1.0, WavExport.tailSeconds(muted), 0.0)

        val orphan = song {
            val base = it.withInstrument(0) { i -> i.copy(sustain = false, decay = 4.0) }
            val unreached = Pattern(name = "B", length = 4, trackCount = base.tracks.size).withNote(0, 0, 60)
            base.copy(patterns = base.patterns + unreached)
        }
        assertEquals("a note in a pattern outside the chain is never heard", 1.0, WavExport.tailSeconds(orphan), 0.0)

        val beyondLength = song {
            it.withInstrument(0) { i -> i.copy(sustain = false, decay = 4.0) }
                .withPattern(0) { p -> p.copy(length = 2) }.setNote(0, 3, 60)
        }
        assertEquals("a note past the pattern's playable length is never reached", 1.0,
            WavExport.tailSeconds(beyondLength), 0.0)

        val onlyNoteOff = song { it.withInstrument(0) { i -> i.copy(sustain = false, decay = 4.0) }.setNote(0, 0, Chip.NOTE_OFF) }
        assertEquals("a note-off makes no sound to ring out", 1.0, WavExport.tailSeconds(onlyNoteOff), 0.0)
    }

    @Test fun defaultOptionsMatchTheOldBehavior() {
        val song = makeSong()
        val plain = WavExport.render(song, temp.root)!!
        val plainBytes = plain.readBytes()
        val explicit = render(song, ExportOptions())
        assertEquals(onePassSamples(song), WavFile.pcm16(plainBytes).size)
        assertArrayEquals("the simple entry point must produce the same file", plainBytes, explicit.readBytes())
    }

    @Test fun loopCountIsClamped() {
        val song = makeSong()
        val pass = onePassSamples(song)
        assertEquals("zero repeats still has to produce a file", pass, samples(render(song, ExportOptions(loopCount = 0))).size)
        assertEquals(pass, samples(render(song, ExportOptions(loopCount = -5))).size)
        assertEquals(pass * ExportOptions.MAX_LOOP_COUNT, samples(render(song, ExportOptions(loopCount = 9999))).size)
        assertEquals(ExportOptions(16), ExportOptions(9999).clamped)
        assertEquals(ExportOptions(1, ExportOptions.TailMode.RING_OUT), ExportOptions(-5, ExportOptions.TailMode.RING_OUT).clamped)
    }

    // MARK: Ending

    @Test fun ringOutEndsInSilence() {
        val audio = samples(render(makeSong(), ExportOptions(1, ExportOptions.TailMode.RING_OUT)))
        assertTrue("a ring-out file must finish on silence", RenderHarness.rms(audio, audio.size - 4410, audio.size) < 0.001)
        assertTrue("the song itself should start straight away", RenderHarness.rms(audio, 0, 2205) > 0.001)
    }

    @Test fun seamlessLoopEndsHot() {
        val song = makeSong().withInstrument(0) { it.copy(decay = 2.0) }
            .setNote(0, 0, Chip.EMPTY_NOTE).setNote(0, 2, Chip.EMPTY_NOTE).setNote(0, 3, 72)
        val audio = samples(render(song, ExportOptions(1, ExportOptions.TailMode.SEAMLESS_LOOP)))
        assertTrue("trailing silence would break the loop", RenderHarness.rms(audio, audio.size - 2205, audio.size) > 0.001)
        assertTrue("the ring-out past the end should be folded over the start", RenderHarness.rms(audio, 0, 2205) > 0.001)
    }

    @Test fun repeatedPassesActuallyRepeatTheMusic() {
        val song = makeSong()
        val pass = onePassSamples(song)
        val audio = samples(render(song, ExportOptions(3, ExportOptions.TailMode.RING_OUT)))
        for (index in 0 until 3) {
            assertTrue("pass $index is silent", RenderHarness.rms(audio, index * pass, (index + 1) * pass) > 0.001)
        }
    }

    @Test fun noOptionCombinationProducesNaNOrClipping() {
        val song = makeSong()
        for (count in listOf(1, 2)) {
            for (mode in ExportOptions.TailMode.entries) {
                val audio = samples(render(song, ExportOptions(count, mode)))
                assertFalse("$count x, $mode", audio.any { !it.isFinite() })
                assertTrue("$count x, $mode", RenderHarness.peak(audio) <= 1.0)
            }
        }
    }

    // MARK: Progress

    @Test fun progressIsMonotonicWithinZeroToOneAndReachesTheEnd() {
        val reported = Collections.synchronizedList(ArrayList<Double>())
        val result = WavExport.render(
            ExportRequest(makeSong(), ExportOptions(3, ExportOptions.TailMode.RING_OUT), progress = { reported.add(it) }),
            temp.root)
        assertTrue("export failed: $result", result is ExportResult.Success)
        val values = reported.toList()
        assertFalse("a multi-second render reported no progress at all", values.isEmpty())
        for (f in values) assertTrue("progress out of range: $f", f in 0.0..1.0)
        assertEquals("progress went backwards", values.sorted(), values)
        assertEquals("progress must finish at 100%", 1.0, values.last(), 0.001)
        assertTrue("progress is throttled to about a hundred calls (${values.size})", values.size <= 102)
    }

    /** A long render reports often enough to move a bar, and no more. */
    @Test fun progressIsThrottledOnALongRender() {
        val song = makeSong().copy(tempo = 40.0)
        val reported = Collections.synchronizedList(ArrayList<Double>())
        val result = WavExport.render(
            ExportRequest(song, ExportOptions(16, ExportOptions.TailMode.RING_OUT), progress = { reported.add(it) }),
            temp.root)
        assertTrue(result is ExportResult.Success)
        assertTrue("too few progress calls (${reported.size})", reported.size >= 50)
        assertTrue("too many progress calls (${reported.size})", reported.size <= 102)
    }

    // MARK: Cancellation

    @Test fun cancelingLeavesNoFileAndReportsCanceledRatherThanFailed() {
        var song = makeSong(name = "Canceled").copy(tempo = 40.0)
        song = song.withPattern(0) { it.copy(length = 64) }
        song = song.copy(arrangement = listOf(song.arrangement[0].copy(repeats = 8)))

        val calls = AtomicInteger(0)
        val result = WavExport.render(
            ExportRequest(song, ExportOptions(4, ExportOptions.TailMode.RING_OUT),
                isCanceled = { calls.incrementAndGet() > 3 }),
            temp.root)
        assertEquals(ExportResult.Canceled, result)

        val dir = File(temp.root, song.id.toString().uppercase())
        val leftovers = dir.list()?.toList() ?: emptyList()
        assertTrue("a canceled export left files behind: $leftovers", leftovers.isEmpty())
        val raw = temp.root.walkTopDown().filter { it.isFile }.toList()
        assertTrue("a canceled export left scratch files behind: $raw", raw.isEmpty())
    }

    /** The write phase polls the cancel token too, and a cancel there must
     * remove the half-written WAV. */
    @Test fun cancelingDuringTheWriteRemovesThePartialFile() {
        var song = makeSong(name = "Late cancel").copy(tempo = 40.0)
        song = song.withPattern(0) { it.copy(length = 64) }
        song = song.copy(arrangement = listOf(song.arrangement[0].copy(repeats = 4)))
        val options = ExportOptions(2, ExportOptions.TailMode.RING_OUT)

        // Count the polls an uncanceled render makes, then cancel on the last
        // one, which is inside the write loop.
        val polls = AtomicInteger(0)
        val ok = WavExport.render(ExportRequest(song, options, isCanceled = { polls.incrementAndGet(); false }), temp.root)
        assertTrue(ok is ExportResult.Success)
        val finished = (ok as ExportResult.Success).file
        assertTrue(finished.exists())

        val calls = AtomicInteger(0)
        val total = polls.get()
        // Through the dispatcher, which is where the app's exports prune.
        val result = ExportRenderer.render(
            ExportRequest(song.copy(name = "Late cancel 2"), options, isCanceled = { calls.incrementAndGet() >= total }),
            temp.root)
        assertEquals(ExportResult.Canceled, result)
        val dir = File(temp.root, song.id.toString().uppercase())
        assertFalse("the half-written WAV was left behind", File(dir, "Late cancel 2.wav").exists())
        assertTrue("a canceled export must not prune the previous one", finished.exists())
        assertTrue("no scratch files left behind", temp.root.listFiles()!!.none { it.isFile })
    }

    @Test fun cancelingBeforeTheFirstChunkStillCancelsCleanly() {
        assertEquals(ExportResult.Canceled,
            WavExport.render(ExportRequest(makeSong(), isCanceled = { true }), temp.root))
    }

    @Test fun anUncanceledExportIsNotReportedAsCanceled() {
        val result = WavExport.render(ExportRequest(makeSong(), isCanceled = { false }), temp.root)
        assertTrue("expected Success, got $result", result is ExportResult.Success)
    }

    @Test fun anOversizedWavIsRejectedBeforeRendering() {
        var song = Song.create("Too Long").copy(tempo = Chip.TEMPO_MIN)
        song = song.withPattern(0) { it.copy(length = Chip.MAX_STEPS) }
        song = song.copy(arrangement = List(8) { SongSection(patternID = song.patterns[0].id, repeats = SongSection.MAX_REPEATS) })
        val started = System.nanoTime()
        val result = WavExport.render(ExportRequest(song, ExportOptions(loopCount = ExportOptions.MAX_LOOP_COUNT)), temp.root)
        assertEquals(ExportResult.TooLong, result)
        assertTrue("size validation happened after rendering began", (System.nanoTime() - started) / 1e9 < 1.0)
    }
}
