package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.model.Track
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ChipCoreConcurrencyTests.swift`. `ChipCore` documents a lock-free
 * contract: the audio thread renders while the main thread rewrites parameters
 * underneath it. These tests are the check - a render loop on one thread while
 * another does everything the UI can do, asserting the output stays finite,
 * inside full scale, and the core's own bounds hold. */
class ChipCoreConcurrencyTest {

    private fun mutationSongs(): List<Song> = (1..Chip.MAX_TRACKS).map { tracks ->
        val trackList = (0 until tracks).map { Track(kind = ChannelKind.entries[it % 4]) }
        val patterns = (0 until 3).map { index ->
            var pattern = Pattern(name = "$index", length = 4 + index * 6, trackCount = tracks)
            for (track in 0 until tracks) pattern = pattern.withNote(track, index, 48 + track * 3)
            pattern
        }
        Song.create("Concurrent $tracks").copy(
            tempo = (90 + tracks * 20).toDouble(),
            tracks = trackList,
            patterns = patterns,
            arrangement = patterns.map { SongSection(patternID = it.id, repeats = 2) },
        ).normalized()
    }

    /** Runs [render] and [mutate] on two threads at once and rethrows the
     * first failure from either. */
    private fun race(render: () -> Unit, mutate: () -> Unit) {
        val failure = AtomicReference<Throwable?>(null)
        val threads = listOf(render, mutate).map { body ->
            Thread {
                try {
                    body()
                } catch (t: Throwable) {
                    failure.compareAndSet(null, t)
                }
            }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join(120_000) }
        assertTrue("a thread did not finish", threads.none { it.isAlive })
        failure.get()?.let { throw it }
    }

    /** Counts samples outside the contract: non-finite, or past full scale. */
    private fun badSamples(buffer: FloatArray): Int {
        var bad = 0
        for (s in buffer) if (!s.isFinite() || s > 1f || s < -1f) bad += 1
        return bad
    }

    @Test fun renderingSurvivesConcurrentParameterWrites() {
        val core = ChipCore(RenderHarness.SAMPLE_RATE)
        val songs = mutationSongs()
        core.load(songs[3])
        core.setSongMode(true)
        core.start()

        val bad = AtomicInteger(0)
        val frames = 512
        // 600 x 512 frames is ~7 s of audio, rendered while the other thread
        // hammers every main-thread entry point.
        val renderPasses = 600
        val energy = AtomicInteger(0)

        race(
            render = {
                val buffer = FloatArray(frames)
                repeat(renderPasses) {
                    core.render(frames, buffer)
                    bad.addAndGet(badSamples(buffer))
                    if (buffer.any { it != 0f }) energy.incrementAndGet()
                }
            },
            mutate = {
                for (pass in 0 until 400) {
                    val song = songs[pass % songs.size]
                    core.load(song)
                    core.setChain(song.chain)
                    core.focus(pass % song.patterns.size)
                    core.setLength(pass % Chip.MAX_PATTERNS, 4 + (pass % 60))
                    core.setNote(pass % Chip.MAX_PATTERNS, pass % Chip.MAX_TRACKS, pass % Chip.MAX_STEPS, 36 + pass % 60)
                    for (track in song.tracks.indices) {
                        core.setInstrument(song.tracks[track].instrument, song.tracks[track].kind, track, pass % 7 == 0)
                    }
                    core.setSongMode(pass % 3 != 0)
                    core.tempo = (60 + pass % 240).toDouble()
                    core.release(pass % Chip.MAX_TRACKS)
                    core.ringingSource(pass % Chip.MAX_TRACKS)
                    if (pass % 11 == 0) core.releaseAll()
                }
            },
        )

        assertEquals("the render produced non-finite or out-of-range samples while parameters were being written",
            0, bad.get())
        assertTrue("the render was silent throughout, so it proves nothing", energy.get() > 0)
        assertTrue(core.trackCount in 1..Chip.MAX_TRACKS)
        assertTrue(core.patternCount in 1..Chip.MAX_PATTERNS)
        assertTrue(core.chainCount in 1..Chip.MAX_CHAIN)
        assertTrue(core.currentPattern < Chip.MAX_PATTERNS)
        assertTrue(core.currentStep < Chip.MAX_STEPS)
    }

    /** Beyond the Swift pass count: the brief asks for a writer hammering
     * instruments, notes, chain and length for the whole of a 2 s+ render,
     * not just for the first 400 passes. */
    @Test fun aWriterHammeringForTheWholeRenderNeverBreaksTheOutput() {
        val core = ChipCore(RenderHarness.SAMPLE_RATE)
        val songs = mutationSongs()
        core.load(songs.last())
        core.setSongMode(true)
        core.start()

        val bad = AtomicInteger(0)
        val writes = AtomicInteger(0)
        val energy = AtomicInteger(0)
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        val frames = 256
        val total = (RenderHarness.SAMPLE_RATE * 3).toInt()

        race(
            render = {
                val buffer = FloatArray(frames)
                var rendered = 0
                while (rendered < total) {
                    core.render(frames, buffer)
                    bad.addAndGet(badSamples(buffer))
                    if (buffer.any { it != 0f }) energy.incrementAndGet()
                    rendered += frames
                }
                done.set(true)
            },
            mutate = {
                var pass = 0
                while (!done.get()) {
                    val song = songs[pass % songs.size]
                    val track = pass % Chip.MAX_TRACKS
                    val inst = song.tracks[track % song.tracks.size].instrument
                    core.setInstrument(inst.copy(sustain = pass % 2 == 0, arpeggio = listOf(0, pass % 24, -(pass % 12))),
                        ChannelKind.entries[pass % 4], track, pass % 13 == 0)
                    core.setNote(pass % Chip.MAX_PATTERNS, track, pass % Chip.MAX_STEPS,
                        if (pass % 5 == 0) Chip.NOTE_OFF else 24 + pass % 90)
                    core.setChain(List(1 + pass % Chip.MAX_CHAIN) { (it * 7 + pass) % Chip.MAX_PATTERNS })
                    core.setLength(pass % Chip.MAX_PATTERNS, pass % 70)
                    if (pass % 17 == 0) core.load(song)
                    pass += 1
                    writes.incrementAndGet()
                }
            },
        )

        assertEquals("non-finite or out-of-range samples under concurrent writes", 0, bad.get())
        assertTrue("the writer barely ran (${writes.get()} passes)", writes.get() > 100)
        assertTrue("the render was silent throughout, so it proves nothing", energy.get() > 0)
    }

    @Test fun chainCursorSurvivesResetsWhileTheChainIsAdvancing() {
        // 200 samples a step: 4000 * 60 / (300 * 4).
        val core = ChipCore(4000.0)
        val patterns = (0 until 4).map { Pattern(name = "$it", length = 4, trackCount = 2).withNote(0, 0, 48 + it) }
        val song = Song.create("Chain churn").copy(
            tracks = (0 until 2).map { Track(kind = ChannelKind.entries[it % 4]) },
            patterns = patterns,
            arrangement = patterns.map { SongSection(patternID = it.id, repeats = 2) },
        ).normalized()
        core.load(song)
        for (index in 0 until Chip.MAX_PATTERNS) core.setLength(index, 1)
        core.tempo = 300.0
        core.setSongMode(true)
        core.start()

        val bad = AtomicInteger(0)
        val boundaries = AtomicInteger(0)
        val frames = 256
        val outOfRange = AtomicReference<String?>(null)

        race(
            render = {
                val buffer = FloatArray(frames)
                var last = core.currentPattern
                repeat(3000) {
                    core.render(frames, buffer)
                    bad.addAndGet(badSamples(buffer))
                    val now = core.currentPattern
                    if (now !in 0 until Chip.MAX_PATTERNS) outOfRange.compareAndSet(null, "pattern $now")
                    if (now != last) {
                        last = now
                        boundaries.incrementAndGet()
                    }
                }
            },
            mutate = {
                for (pass in 0 until 20000) {
                    core.setSongMode(pass % 8 != 0)
                    core.setChain((0 until (1 + pass % 4)).toList())
                }
            },
        )

        assertEquals(0, bad.get())
        assertNull(outOfRange.get())
        assertTrue("the render never crossed enough pattern boundaries (${boundaries.get()}) to exercise the cursor",
            boundaries.get() > 500)
        assertTrue(core.currentPattern in 0 until Chip.MAX_PATTERNS)
    }

    @Test fun releaseTokensSurviveConcurrentTriggering() {
        val core = ChipCore(4000.0)
        var pattern = Pattern(name = "0", length = 16, trackCount = Chip.MAX_TRACKS)
        for (track in 0 until Chip.MAX_TRACKS) {
            for (step in 0 until 16) pattern = pattern.withNote(track, step, 48 + (track + step) % 24)
        }
        val song = Song.create("Release churn").copy(
            tracks = (0 until Chip.MAX_TRACKS).map { Track(kind = ChannelKind.entries[it % 4]) },
            patterns = listOf(pattern),
            arrangement = listOf(SongSection(patternID = pattern.id, repeats = 1)),
        ).normalized()
        core.load(song)
        core.tempo = 300.0
        core.start()

        val bad = AtomicInteger(0)
        val steps = AtomicInteger(0)
        val frames = 256

        race(
            render = {
                val buffer = FloatArray(frames)
                var last = core.currentStep
                repeat(3000) {
                    core.render(frames, buffer)
                    bad.addAndGet(badSamples(buffer))
                    if (core.currentStep != last) {
                        last = core.currentStep
                        steps.incrementAndGet()
                    }
                }
            },
            mutate = {
                for (pass in 0 until 20000) {
                    core.release(pass % Chip.MAX_TRACKS)
                    if (pass % 4 == 0) core.releaseAll()
                }
            },
        )

        assertEquals(0, bad.get())
        assertTrue("the playhead barely moved (${steps.get()}), so the audio thread was not triggering",
            steps.get() > 500)
    }

    @Test fun transportChangesDuringRenderStayFinite() {
        val core = ChipCore(RenderHarness.SAMPLE_RATE)
        core.load(TestSongs.golden().normalized())
        core.start()
        val bad = AtomicInteger(0)
        val energy = AtomicInteger(0)

        race(
            render = {
                val buffer = FloatArray(256)
                repeat(1500) {
                    core.render(256, buffer)
                    bad.addAndGet(badSamples(buffer))
                    if (buffer.any { it != 0f }) energy.incrementAndGet()
                }
            },
            mutate = {
                for (pass in 0 until 800) {
                    if (pass % 2 == 0) core.start() else core.stop()
                    core.audition(pass % 4, 48 + pass % 40)
                    core.finish()
                }
            },
        )
        assertEquals(0, bad.get())
        assertTrue("the render was silent throughout, so it proves nothing", energy.get() > 0)
    }
}
