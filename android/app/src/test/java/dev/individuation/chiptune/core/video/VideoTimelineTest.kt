package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.ExportRequest
import dev.individuation.chiptune.core.audio.ExportResult
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.audio.WavFile
import dev.individuation.chiptune.core.audio.setNote
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import java.io.File
import kotlin.math.ceil
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of `VideoTimelineTests.swift`: which step each video frame shows.
 * The picture is only worth anything if it agrees with the audio sample for
 * sample, so these pin the mapping to the same step length and chain the WAV
 * renderer plays, and to the fixture iOS reads too. */
class VideoTimelineTest {

    @get:Rule val temp = TemporaryFolder()

    private fun videoOptions(loops: Int = 1) =
        ExportOptions(loops, ExportOptions.TailMode.SEAMLESS_LOOP, ExportOptions.Format.VIDEO)

    /** 150 BPM is 4410 samples a step: exactly three frames. */
    private fun evenSong(): Song = TestSongs.empty(name = "Even", tempo = 150.0, length = 4).setNote(0, 0, 60)

    private fun at(slot: Int, pattern: Int, step: Int) = VideoTimeline.Position(slot, pattern, step)

    @Test fun frameZeroIsTheFirstStep() {
        assertEquals(at(0, 0, 0), VideoTimeline(evenSong(), videoOptions()).position(0))
    }

    @Test fun aFrameOnAStepBoundaryShowsTheNewStep() {
        val timeline = VideoTimeline(evenSong(), videoOptions())
        assertEquals(3 * VideoTimeline.SAMPLES_PER_FRAME, timeline.samplesPerStep)
        assertEquals(0, timeline.position(2)?.step)
        assertEquals(1, timeline.position(3)?.step)
        assertEquals(3, timeline.position(11)?.step)
    }

    /** Repeats expand into chain slots, so the second play of a section is
     * its own slot even though it shows the same pattern. */
    @Test fun sectionRepeatsWalkTheChain() {
        val song = TestSongs.twoPatterns(lengths = 4 to 4, repeats = 2 to 1, tempo = 150.0)
        val timeline = VideoTimeline(song, videoOptions())
        val perPattern = 4 * 3
        assertEquals(at(0, 0, 0), timeline.position(0))
        assertEquals(at(1, 0, 0), timeline.position(perPattern))
        assertEquals(at(2, 1, 1), timeline.position(2 * perPattern + 3))
    }

    @Test fun theSecondPassStartsAgainAtSlotZero() {
        val song = TestSongs.twoPatterns(lengths = 4 to 4, repeats = 1 to 1, tempo = 150.0)
        val timeline = VideoTimeline(song, videoOptions(loops = 2))
        val onePass = 8 * 3
        assertEquals(at(1, 1, 3), timeline.position(onePass - 1))
        assertEquals(at(0, 0, 0), timeline.position(onePass))
    }

    @Test fun tailFramesShowNoStepAndTheFrameCountCoversTheAudio() {
        val song = evenSong()
        val timeline = VideoTimeline(song, videoOptions())
        val body = 4 * 4410
        val tail = (44100 * WavExport.tailSeconds(song)).toInt()
        assertEquals(body, timeline.bodySamples)
        assertEquals(tail, timeline.tailSamples)
        assertEquals(body + tail, timeline.totalSamples)
        assertEquals(ceil((body + tail).toDouble() / 44100 * 30).toInt(), timeline.totalFrames)
        assertNotNull(timeline.position(body / 1470 - 1))
        assertNull(timeline.position(body / 1470))
        assertNull(timeline.position(timeline.totalFrames - 1))
    }

    /** The timeline's length is the soundtrack's length, so the video ends
     * with its audio rather than cutting it or running on in silence. */
    @Test fun theTotalIsTheLengthOfTheRenderedSoundtrack() {
        val song = TestSongs.twoPatterns(lengths = 16 to 8, repeats = 2 to 1, tempo = 133.0)
        val options = videoOptions(loops = 2)
        val scratch = File(temp.root, "timeline.wav")
        val result = WavExport.render(ExportRequest(song, options), temp.root, scratch)
        assertTrue("render failed: $result", result is ExportResult.Success)
        assertEquals(WavFile.pcm16(scratch).size, VideoTimeline(song, options).totalSamples)
    }

    /** The renderer normalizes first, and so does the timeline: an imported
     * tempo past the range plays at 300 BPM, so it must draw at 300 too. */
    @Test fun theSongIsNormalizedFirst() {
        val timeline = VideoTimeline(evenSong().copy(tempo = 1000.0), videoOptions())
        assertEquals(Chip.samplesPerStep(300.0, 44100.0), timeline.samplesPerStep)
    }

    // MARK: Shared fixture

    private fun fixture(): JSONObject {
        val stream = javaClass.classLoader!!.getResourceAsStream("video-timeline.json")
            ?: error("video-timeline.json is not on the test classpath (sourceSets test resources → ../../Tests/Fixtures)")
        return JSONObject(String(stream.use { it.readBytes() }, Charsets.UTF_8))
    }

    /** iOS reads the same file, so both platforms draw the same step on the
     * same frame. */
    @Test fun theSharedFixtureMatches() {
        val fixture = fixture()
        assertEquals(WavExport.SAMPLE_RATE.toInt(), fixture.getInt("sampleRate"))
        assertEquals(VideoTimeline.FPS, fixture.getInt("fps"))
        assertEquals(VideoTimeline.SAMPLES_PER_FRAME, fixture.getInt("samplesPerFrame"))

        val song = SongDocument.decode(fixture.getJSONObject("song").toString().toByteArray(Charsets.UTF_8))
        val expected = fixture.getJSONObject("expected")
        val timeline = VideoTimeline(song, videoOptions(loops = fixture.getInt("loopCount")))
        assertEquals(expected.getInt("samplesPerStep"), timeline.samplesPerStep)
        val chain = expected.getJSONArray("chain").let { a -> List(a.length()) { a.getInt(it) } }
        assertEquals(chain, timeline.chain)
        assertEquals(expected.getInt("arrangementSteps"), song.arrangementSteps)
        assertEquals(expected.getInt("bodySamples"), timeline.bodySamples)
        assertEquals(expected.getInt("tailSamples"), timeline.tailSamples)
        assertEquals(expected.getInt("totalSamples"), timeline.totalSamples)
        assertEquals(expected.getInt("totalFrames"), timeline.totalFrames)

        val frames = fixture.getJSONArray("frames")
        assertEquals(expected.getInt("totalFrames"), frames.length())
        for (i in 0 until frames.length()) {
            val row = frames.getJSONObject(i)
            val frame = row.getInt("frame")
            val want = if (row.isNull("chainSlot")) {
                null
            } else {
                at(row.getInt("chainSlot"), row.getInt("pattern"), row.getInt("step"))
            }
            assertEquals("frame $frame", want, timeline.position(frame))
        }
    }
}
