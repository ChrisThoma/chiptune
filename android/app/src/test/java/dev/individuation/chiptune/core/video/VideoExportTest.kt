package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.ExportFiles
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.ExportRenderer
import dev.individuation.chiptune.core.audio.ExportRequest
import dev.individuation.chiptune.core.audio.ExportResult
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.audio.WavFile
import dev.individuation.chiptune.core.audio.setNote
import dev.individuation.chiptune.core.audio.withPattern
import dev.individuation.chiptune.core.model.Song
import java.io.File
import java.io.IOException
import java.util.Collections
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The JVM half of `VideoExportTests.swift`: everything around the encoder.
 * The soundtrack is rendered first to a scratch WAV outside the song's export
 * folder, the writer is handed it with the timeline, and the finished mp4
 * replaces the song's last video only once it is complete. Nothing
 * half-made is left behind however it ends. The encoder itself
 * (`platform/video/Mp4Writer`) needs MediaCodec and is checked on a device. */
class VideoExportTest {

    @get:Rule val temp = TemporaryFolder()

    private fun song(name: String = "Clip"): Song =
        TestSongs.empty(name = name, tempo = 240.0, length = 4).setNote(0, 0, 60)

    private fun video(style: ExportOptions.VideoStyle = ExportOptions.VideoStyle.GRID, loops: Int = 1) =
        ExportOptions(loops, ExportOptions.TailMode.SEAMLESS_LOOP, ExportOptions.Format.VIDEO, style)

    /** Writes a recognisable file to the job's output and remembers the job. */
    private open class FakeWriter(val bytes: ByteArray = byteArrayOf(1, 2, 3)) : VideoWriter {
        val jobs = ArrayList<VideoJob>()
        var soundtrackSamples = -1
        var soundtrackExisted = false
        override fun write(job: VideoJob): ExportResult {
            jobs.add(job)
            soundtrackExisted = job.soundtrack.exists()
            soundtrackSamples = WavFile.pcm16(job.soundtrack).size
            for (f in 0..10) job.progress(f / 10.0)
            job.output.writeBytes(bytes)
            return ExportResult.Success(job.output)
        }
    }

    private val scratch: File get() = File(temp.root, VideoExport.SCRATCH_DIRECTORY)

    private fun scratchFiles(): List<String> = scratch.list()?.toList() ?: emptyList()

    @Test fun aVideoLandsAtTheSongsMp4AndTheScratchIsCleared() {
        val writer = FakeWriter()
        val song = song()
        val result = ExportRenderer.render(ExportRequest(song, video()), temp.root, writer)
        val expected = ExportFiles.file(song, temp.root, ExportOptions.Format.VIDEO)
        assertEquals(ExportResult.Success(expected), result)
        assertArrayEquals(byteArrayOf(1, 2, 3), expected.readBytes())
        assertEquals("scratch left behind: ${scratchFiles()}", emptyList<String>(), scratchFiles())
        assertTrue("no raw files at the root", temp.root.listFiles()!!.none { it.isFile })
    }

    /** The writer gets a soundtrack exactly as long as the timeline, with the
     * ring-out, and an output in the scratch folder rather than the song's. */
    @Test fun theWriterGetsTheSoundtrackAndTheTimeline() {
        val writer = FakeWriter()
        val song = song()
        val options = video(ExportOptions.VideoStyle.COVER, loops = 2)
        ExportRenderer.render(ExportRequest(song, options), temp.root, writer)
        val job = writer.jobs.single()
        assertTrue(writer.soundtrackExisted)
        assertEquals(VideoTimeline(song, options).totalSamples, writer.soundtrackSamples)
        assertEquals(VideoTimeline(song, options).totalFrames, job.timeline.totalFrames)
        assertEquals(ExportOptions.VideoStyle.COVER, job.options.videoStyle)
        assertEquals(2, job.options.loopCount)
        assertEquals(scratch, job.output.parentFile)
        assertEquals(scratch, job.soundtrack.parentFile)
        assertEquals("mp4", job.output.extension)
    }

    /** Rendering the soundtrack must not replace the WAV the user last exported. */
    @Test fun theUsersWavIsUntouched() {
        val song = song()
        val wav = (WavExport.render(ExportRequest(song), temp.root) as ExportResult.Success).file
        val before = wav.readBytes()
        ExportRenderer.render(ExportRequest(song, video()), temp.root, FakeWriter())
        assertArrayEquals(before, wav.readBytes())
    }

    @Test fun progressRisesToOneWithTheSoundtrackFirst() {
        val reported = Collections.synchronizedList(ArrayList<Double>())
        val result = ExportRenderer.render(
            ExportRequest(song(), video(), progress = { reported.add(it) }), temp.root, FakeWriter())
        assertTrue(result is ExportResult.Success)
        val values = reported.toList()
        assertEquals("progress went backwards: $values", values.sorted(), values)
        assertEquals(1.0, values.last(), 0.0)
        assertTrue(values.all { it in 0.0..1.0 })
        // The audio takes the first 30%; the writer's 0..1 maps onto the rest.
        assertTrue(values.any { it > 0.0 && it <= 0.3 + 1e-9 })
        assertTrue(values.any { it > 0.3 + 1e-9 && it < 1.0 })
    }

    /** A video longer than TikTok's ten minutes is refused from the timeline,
     * before any audio or frames are rendered. */
    @Test fun anOverlongVideoIsRefusedBeforeRendering() {
        var slow = song().copy(tempo = 30.0).withPattern(0) { it.copy(length = 64) }
        slow = slow.copy(arrangement = listOf(slow.arrangement[0].copy(repeats = 8)))
        assertTrue(VideoTimeline(slow, video(loops = 4)).seconds > VideoExport.MAX_SECONDS)
        val writer = FakeWriter()
        val started = System.nanoTime()
        val result = ExportRenderer.render(ExportRequest(slow, video(loops = 4)), temp.root, writer)
        assertEquals(ExportResult.TooLong, result)
        assertTrue(writer.jobs.isEmpty())
        assertTrue((System.nanoTime() - started) / 1e9 < 1.0)
        assertTrue("nothing written", temp.root.walkTopDown().none { it.isFile })
    }

    @Test fun exactlyTenMinutesIsAllowed() {
        assertEquals(600.0, VideoExport.MAX_SECONDS, 0.0)
    }

    @Test fun aCanceledWriterLeavesNothingAndKeepsThePreviousVideo() {
        val song = song()
        val previous = (ExportRenderer.render(ExportRequest(song, video()), temp.root, FakeWriter(byteArrayOf(9))) as ExportResult.Success).file
        val canceling = object : FakeWriter() {
            override fun write(job: VideoJob): ExportResult {
                job.output.writeBytes(byteArrayOf(7, 7))
                return ExportResult.Canceled
            }
        }
        assertEquals(ExportResult.Canceled, ExportRenderer.render(ExportRequest(song, video()), temp.root, canceling))
        assertArrayEquals(byteArrayOf(9), previous.readBytes())
        assertEquals(emptyList<String>(), scratchFiles())
    }

    @Test fun aFailedWriterLeavesNothingAndKeepsThePreviousVideo() {
        val song = song()
        val previous = (ExportRenderer.render(ExportRequest(song, video()), temp.root, FakeWriter(byteArrayOf(9))) as ExportResult.Success).file
        val failing = object : FakeWriter() {
            override fun write(job: VideoJob): ExportResult {
                job.output.writeBytes(byteArrayOf(7, 7))
                return ExportResult.Failed(IOException("encoder died"))
            }
        }
        val result = ExportRenderer.render(ExportRequest(song, video()), temp.root, failing)
        assertTrue(result is ExportResult.Failed)
        assertArrayEquals(byteArrayOf(9), previous.readBytes())
        assertEquals(emptyList<String>(), scratchFiles())
    }

    /** A writer that throws is a failure, not a crash, and still cleans up. */
    @Test fun aThrowingWriterIsAFailure() {
        val throwing = object : FakeWriter() {
            override fun write(job: VideoJob): ExportResult {
                job.output.writeBytes(byteArrayOf(7))
                throw IllegalStateException("codec")
            }
        }
        val result = ExportRenderer.render(ExportRequest(song(), video()), temp.root, throwing)
        assertTrue("$result", result is ExportResult.Failed)
        assertEquals(emptyList<String>(), scratchFiles())
    }

    /** Canceled while the soundtrack renders: the writer never runs. */
    @Test fun cancelingDuringTheSoundtrackNeverStartsTheWriter() {
        val writer = FakeWriter()
        val result = ExportRenderer.render(ExportRequest(song(), video(), isCanceled = { true }), temp.root, writer)
        assertEquals(ExportResult.Canceled, result)
        assertTrue(writer.jobs.isEmpty())
        assertEquals(emptyList<String>(), scratchFiles())
    }

    /** Without a writer (the JVM, or a caller that didn't pass one) a video
     * export fails rather than pretending. */
    @Test fun noWriterIsAFailure() {
        val result = ExportRenderer.render(ExportRequest(song(), video()), temp.root)
        assertTrue("$result", result is ExportResult.Failed)
        assertNotNull((result as ExportResult.Failed).error.message)
    }

    /** The video goes through the dispatcher's pruning like the others: a
     * renamed song's old video goes, its WAV under the new name stays. */
    @Test fun aVideoExportPrunesLikeTheOthers() {
        var song = song("Old")
        val first = (ExportRenderer.render(ExportRequest(song, video()), temp.root, FakeWriter()) as ExportResult.Success).file
        song = song.copy(name = "New")
        ExportRenderer.render(ExportRequest(song), temp.root)
        ExportRenderer.render(ExportRequest(song, video()), temp.root, FakeWriter())
        assertFalse(first.exists())
        assertEquals(setOf("New.wav", "New.mp4"), first.parentFile!!.list()!!.toSet())
    }
}
