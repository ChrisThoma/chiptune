package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.ExportFiles
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.ExportResult
import dev.individuation.chiptune.core.audio.RenderHarness
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.model.Song
import java.io.File
import java.io.IOException
import java.nio.file.AccessDeniedException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun scratchWav(tag: String): File = File(System.getProperty("java.io.tmpdir"), "$tag-${UUID.randomUUID()}.wav")

/** Port of `StudioExportTests.swift`, the Studio half of
 * `ExportOptionsTests.swift`, and the export cases of `ErrorSurfacingTests`. */
class StudioExportTest {

    private val harnesses = ArrayList<StudioHarness>()

    private fun make(renderer: ((dev.individuation.chiptune.core.audio.ExportRequest) -> ExportResult)? = null): StudioHarness =
        StudioHarness(renderer = renderer).also { harnesses.add(it) }

    @After
    fun tearDown() = harnesses.forEach { it.close() }

    @Test fun exportRunsAsyncAndPublishesAPlayableFile() {
        val h = make()
        h.studio.exportFile = File("/stale/from/last/time.wav")

        h.studio.export()

        assertTrue("still running right after the call returns", h.studio.isExporting)
        assertNull("a stale file must not survive the start of a new export", h.studio.exportFile)

        h.waitForExport()

        val file = h.studio.exportFile!!
        assertTrue(file.exists())
        assertTrue(file.length() > 44)
        assertEquals("RIFF", String(file.readBytes().copyOfRange(0, 4)))
    }

    /** The result dialog names the song as titled, not its sanitised file
     * name, and a rename after the export doesn't change it. */
    @Test fun aFinishedExportCarriesTheSongsOwnTitle() {
        val h = make()
        h.studio.open(Song.create("Mega Man's Theme!"))
        h.studio.edit { it.withNote(0, 0, 0, 60) }
        h.studio.export()
        assertNull(h.studio.exportTitle)
        h.waitForExport()
        assertEquals("Mega Mans Theme.wav", h.studio.exportFile!!.name)
        assertEquals("Mega Man's Theme!", h.studio.exportTitle)
    }

    @Test fun secondExportWhileBusyIsIgnored() {
        val h = make()
        val first = h.studio.export()
        assertNotNull(first)
        assertTrue(h.studio.isExporting)
        assertNull(h.studio.export())
        assertTrue(h.studio.isExporting)
        h.waitForExport()
        assertNotNull(h.studio.exportFile)
    }

    /** The same song in the same format writes the same path, so the file
     * alone can't tell the second success from the first; the attempt
     * counter has to move for each, with the file published. */
    @Test fun twoSuccessesToTheSamePathEachAdvanceTheAttempt() {
        val standIn = File(System.getProperty("java.io.tmpdir"), "same-${UUID.randomUUID()}.mid")
        val h = make { ExportResult.Success(standIn) }
        val first = h.studio.export()
        h.waitForExport()
        assertEquals(first, h.studio.completedExportAttempt)
        assertEquals(standIn, h.studio.exportFile)

        val second = h.studio.export()
        h.waitForExport()
        assertEquals(second, h.studio.completedExportAttempt)
        assertEquals(first!! + 1, second)
        assertEquals(standIn, h.studio.exportFile)
    }

    @Test fun exportUsesTheInjectedRenderer() {
        val standIn = scratchWav("injected")
        val h = make()
        h.studio.renderer = { ExportResult.Success(standIn) }
        h.studio.export()
        h.waitForExport()
        assertEquals(standIn, h.studio.exportFile)
    }

    // MARK: Studio's side of export options

    @Test fun evenImmediateCompletionsPublishDistinctAttemptTokens() {
        val h = make { ExportResult.Failed(IOException("boom")) }
        val first = h.studio.export()
        h.waitForExport()
        assertEquals(first, h.studio.completedExportAttempt)
        h.studio.renderer = { ExportResult.Canceled }
        val second = h.studio.export()
        h.waitForExport()
        assertEquals(second, h.studio.completedExportAttempt)
        assertNotEquals(first, second)
    }

    @Test fun progressArrivingAfterFinishDoesNotResurrectTheBar() {
        val stashed = AtomicReference<((Double) -> Unit)?>(null)
        val h = make { request ->
            stashed.set(request.progress)
            ExportResult.Success(scratchWav("stale"))
        }
        h.studio.export()
        h.waitForExport()
        assertEquals(0.0, h.studio.exportProgress, 0.0)

        stashed.get()!!(0.7)
        h.scheduler.runPosted()

        assertEquals(0.0, h.studio.exportProgress, 0.0)
    }

    @Test fun staleProgressFromPreviousExportCannotOverwriteActiveExport() {
        val stashedA = AtomicReference<((Double) -> Unit)?>(null)
        val h = make { request ->
            stashedA.set(request.progress)
            ExportResult.Success(scratchWav("a"))
        }
        h.studio.export()
        h.waitForExport()

        val bStarted = CountDownLatch(1)
        val releaseB = AtomicBoolean(false)
        h.studio.renderer = { request ->
            bStarted.countDown()
            while (!releaseB.get()) Thread.sleep(1)
            request.progress(0.3)
            ExportResult.Success(scratchWav("b"))
        }
        h.studio.export()
        assertTrue(bStarted.await(10, TimeUnit.SECONDS))

        stashedA.get()!!(0.9)
        h.scheduler.runPosted()

        assertNotEquals(0.9, h.studio.exportProgress, 0.0)
        releaseB.set(true)
        h.waitForExport()
    }

    @Test fun canceledExportPublishesNoFileAndNoError() {
        val h = make { ExportResult.Canceled }
        h.studio.export()
        h.waitForExport()
        assertNull(h.studio.exportFile)
        assertNull("canceling is not an error", h.studio.exportError)
        assertEquals(0.0, h.studio.exportProgress, 0.0)
    }

    @Test fun cancelExportReachesTheRenderer() {
        val started = CountDownLatch(1)
        val h = make { request ->
            started.countDown()
            while (!request.isCanceled()) Thread.sleep(1)
            ExportResult.Canceled
        }
        h.studio.export()
        assertTrue(started.await(10, TimeUnit.SECONDS))
        h.studio.cancelExport()
        h.waitForExport()
        assertFalse(h.studio.isExporting)
        assertNull(h.studio.exportError)
    }

    @Test fun progressReachesTheStudio() {
        val gate = CountDownLatch(1)
        val h = make { request ->
            request.progress(0.5)
            gate.await(10, TimeUnit.SECONDS)
            ExportResult.Success(scratchWav("progress"))
        }
        h.studio.export()
        val deadline = System.nanoTime() + 10_000_000_000L
        while (h.studio.exportProgress != 0.5 && System.nanoTime() < deadline) {
            h.scheduler.runPosted()
            Thread.sleep(1)
        }
        assertEquals(0.5, h.studio.exportProgress, 0.0)
        assertEquals("the state flow carries it", 0.5, h.studio.state.value.exportProgress, 0.0)
        gate.countDown()
        h.waitForExport()
        assertNotNull(h.studio.exportFile)
        assertEquals("reset once finished", 0.0, h.studio.exportProgress, 0.0)
    }

    /** A video reports every frame; the Studio posts a state copy only once
     * the bar has moved a whole percent, or reached the end. */
    @Test fun progressIsPostedOncePerPercentNotPerFrame() {
        val reported = CountDownLatch(1)
        val gate = CountDownLatch(1)
        val h = make { request ->
            for (i in 1..10_000) request.progress(i / 10_000.0)
            reported.countDown()
            gate.await(10, TimeUnit.SECONDS)
            ExportResult.Canceled
        }
        h.studio.export()
        assertTrue(reported.await(10, TimeUnit.SECONDS))
        val posts = h.scheduler.runPosted()
        assertTrue("posted $posts updates for 10,000 frames", posts in 90..101)
        assertEquals("completion is still posted", 1.0, h.studio.exportProgress, 0.0)
        gate.countDown()
        h.waitForExport()
    }

    @Test fun progressThrottleAdmitsWholePercentStepsAndCompletion() {
        val throttle = ExportProgressThrottle()
        assertFalse(throttle.admits(0.004))
        assertTrue(throttle.admits(0.01))
        assertFalse(throttle.admits(0.015))
        assertTrue(throttle.admits(0.02))
        assertTrue("completion always gets through", ExportProgressThrottle().admits(1.0))
        val nearEnd = ExportProgressThrottle()
        assertTrue(nearEnd.admits(0.995))
        assertTrue("reaching 1 is posted even under a percent on", nearEnd.admits(1.0))
        assertFalse("but only once", nearEnd.admits(1.0))
    }

    /** Every song keeps its last export (a video is ~60 MB a minute) until
     * the app starts with it over a day old, which clears it. */
    @Test fun startingTheStudioSweepsEarlierExports() {
        val dir = java.nio.file.Files.createTempDirectory("chiptune-export-").toFile()
        val old = File(dir, UUID.randomUUID().toString().uppercase()).also { it.mkdirs() }
        File(old, "Old.mp4").apply {
            writeText("video")
            setLastModified(System.currentTimeMillis() - 2 * ExportFiles.SWEEP_MIN_AGE_MILLIS)
        }
        val h = StudioHarness(exportDir = dir).also { harnesses.add(it) }
        h.drainExecutor()
        assertFalse(old.exists())
    }

    /** A recent export may still be open in the app it was shared to. */
    @Test fun startingTheStudioKeepsARecentExport() {
        val dir = java.nio.file.Files.createTempDirectory("chiptune-export-").toFile()
        val recent = File(File(dir, UUID.randomUUID().toString().uppercase()).also { it.mkdirs() }, "Shared.wav")
        recent.writeText("audio")
        val h = StudioHarness(exportDir = dir).also { harnesses.add(it) }
        h.drainExecutor()
        assertTrue(recent.exists())
    }

    @Test fun deletingASongRemovesItsExportFolder() {
        val h = make()
        val doomed = Song.create("Doomed")
        h.studio.open(doomed)
        h.studio.edit { it.withNote(0, 0, 0, 60) }
        h.studio.export()
        h.waitForExport()
        val folder = h.studio.exportFile!!.parentFile!!
        assertTrue(folder.isDirectory)

        h.studio.delete(h.studio.song)
        h.drainExecutor()

        assertFalse(folder.exists())
    }

    @Test fun optionsReachTheRenderer() {
        val seen = AtomicReference<ExportOptions?>(null)
        val h = make { request ->
            seen.set(request.options)
            ExportResult.Success(scratchWav("opts"))
        }
        h.studio.export(ExportOptions(loopCount = 4, tailMode = ExportOptions.TailMode.RING_OUT))
        h.waitForExport()
        assertEquals(ExportOptions(loopCount = 4, tailMode = ExportOptions.TailMode.RING_OUT), seen.get())
    }

    /** A renderer that throws is a failed export, not a stuck busy flag. */
    @Test fun aRendererThatThrowsIsReportedAsAFailure() {
        val h = make { throw IllegalStateException("kaboom") }
        h.studio.export()
        h.waitForExport()
        assertFalse(h.studio.isExporting)
        assertNotNull(h.studio.exportError)
    }

    // MARK: Error surfacing

    @Test fun aFailedExportIsReported() {
        val h = make { ExportResult.Failed(IOException("write failed")) }
        h.studio.export()
        h.waitForExport()
        assertNull(h.studio.exportFile)
        assertFalse(h.studio.isExporting)
        assertTrue(h.studio.exportError!!.contains(h.studio.song.name))
    }

    @Test fun aReadOnlyExportFolderBlamesPermissionNotSpace() {
        val h = make()
        h.studio.open(Song.create("Locked Out"))
        h.exportDir.setWritable(false)
        try {
            h.studio.export()
            h.waitForExport()
        } finally {
            h.exportDir.setWritable(true)
        }
        assertNull(h.studio.exportFile)
        val message = h.studio.exportError!!
        assertTrue(message, message.contains("\u201CLocked Out\u201D"))
        assertTrue(message, message.lowercase().contains("permission"))
        assertFalse(message, message.lowercase().contains("space"))
        assertFalse(message, message.contains("Try again"))
    }

    @Test fun aTooLongExportGetsSpecificAdvice() {
        val h = make { ExportResult.TooLong }
        h.studio.export()
        h.waitForExport()
        assertEquals("Too long for one WAV. Lower the repeat count.", h.studio.exportError)
    }

    /** A video's limit is the ten minutes TikTok takes, not the WAV's RIFF
     * size, so its alert says so. Port of iOS's too-long cases. */
    @Test fun aTooLongVideoNamesTheTenMinuteCap() {
        val text = ExportTooLongMessage.text(ExportOptions.Format.VIDEO)
        assertTrue(text, text.contains("10 minutes"))
        assertNotEquals(ExportTooLongMessage.text(ExportOptions.Format.WAV), text)
    }

    @Test fun aTooLongWavKeepsItsWording() {
        assertEquals("Too long for one WAV. Lower the repeat count.", ExportTooLongMessage.text(ExportOptions.Format.WAV))
    }

    @Test fun aTooLongVideoExportShowsTheVideoMessage() {
        val h = make { ExportResult.TooLong }
        h.studio.exportOptions = ExportOptions(format = ExportOptions.Format.VIDEO)
        h.studio.export()
        h.waitForExport()
        assertEquals(ExportTooLongMessage.text(ExportOptions.Format.VIDEO), h.studio.exportError)
    }

    @Test fun aSuccessfulExportReportsNoError() {
        val file = scratchWav("ok")
        val h = make { ExportResult.Success(file) }
        h.studio.export()
        h.waitForExport()
        assertEquals(file, h.studio.exportFile)
        assertNull(h.studio.exportError)
    }

    @Test fun retryingAfterAFailureClearsTheMessage() {
        val h = make { ExportResult.Failed(AccessDeniedException("x")) }
        h.studio.export()
        h.waitForExport()
        assertNotNull(h.studio.exportError)
        val file = scratchWav("retry")
        h.studio.renderer = { ExportResult.Success(file) }
        h.studio.export()
        h.waitForExport()
        assertNull(h.studio.exportError)
    }

    /** Export builds its own core rather than borrowing the live one. */
    @Test fun exportingMidPlaybackDoesNotDisturbTheLiveCore() {
        val h = make()
        h.studio.open(TestSongs.golden().copy(tempo = 132.0))
        h.studio.setSongMode(true)
        val core = h.studio.core
        core.start()
        RenderHarness.renderMono(core, 20_000)
        val stepBefore = core.currentStep
        val patternBefore = core.currentPattern
        assertTrue(stepBefore > 0)

        assertNotNull(WavExport.render(h.studio.song, h.exportDir))

        assertEquals(stepBefore, core.currentStep)
        assertEquals(patternBefore, core.currentPattern)
        assertTrue(core.playing)
    }

    // MARK: The chosen format

    @Test fun optionsStartAsAWavWithTheDefaultRepeatsAndEnding() {
        assertEquals(ExportOptions(), make().studio.exportOptions)
    }

    /** The choice lives in Studio, not the sheet, so it outlasts the sheet closing. */
    @Test fun theChosenOptionsSurviveAnExport() {
        val h = make()
        h.studio.exportOptions = ExportOptions(3, ExportOptions.TailMode.RING_OUT, ExportOptions.Format.MIDI)
        h.studio.open(TestSongs.golden())
        h.studio.export()
        h.waitForExport()
        assertEquals(ExportOptions.Format.MIDI, h.studio.exportOptions.format)
        assertEquals(3, h.studio.exportOptions.loopCount)
    }

    /** The export options are one export's, not the app's: when the flow
     * ends, the next opening starts at WAV, 1x, Seamless loop. */
    @Test fun endingTheExportFlowPutsTheOptionsBackToTheDefaults() {
        val h = make()
        h.studio.exportOptions = ExportOptions(3, ExportOptions.TailMode.RING_OUT, ExportOptions.Format.MIDI)

        h.studio.endExportFlow()

        assertEquals(ExportOptions(), h.studio.exportOptions)
        assertEquals(ExportOptions(), ExportOptions(1, ExportOptions.TailMode.SEAMLESS_LOOP, ExportOptions.Format.WAV))
    }

    /** Nothing is injected, so this is the dispatcher the app ships with: the
     * format the sheet picked has to reach the writer. */
    @Test fun defaultRendererFollowsTheChosenFormat() {
        val h = StudioHarness(renderer = null).also { harnesses.add(it) }
        h.studio.open(TestSongs.golden())
        h.studio.exportOptions = ExportOptions(format = ExportOptions.Format.MIDI)
        h.studio.export()
        h.waitForExport()
        assertEquals("mid", h.studio.exportFile!!.extension)

        h.studio.exportOptions = ExportOptions(format = ExportOptions.Format.WAV)
        h.studio.export()
        h.waitForExport()
        assertEquals("wav", h.studio.exportFile!!.extension)
    }

    @Test fun aMidiExportFailureCallsTheFileAMidiFile() {
        val h = make { ExportResult.Failed(AccessDeniedException("/x")) }
        h.studio.exportOptions = ExportOptions(format = ExportOptions.Format.MIDI)
        h.studio.export()
        h.waitForExport()
        val message = h.studio.exportError!!
        assertTrue(message, message.contains("MIDI file"))
        assertFalse(message, message.contains("WAV"))
    }
}
