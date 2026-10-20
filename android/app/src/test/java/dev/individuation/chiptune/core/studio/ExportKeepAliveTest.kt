package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.ExportRequest
import dev.individuation.chiptune.core.audio.ExportResult
import java.io.File
import java.io.IOException
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of iOS's `InterruptedExportMessageTests`: the words for a video render
 * that failed after the app left the screen. Retrying in the same way fails
 * the same way; staying in the app is what fixes it. */
class InterruptedExportMessageTest {
    private val generic = IllegalStateException("Failed to stop the muxer")
    private val keepOpen = "Couldn't export “Clip”. Keep Chiptune open while the video renders."

    /** The encoder gives up in the background with whatever error it likes. */
    @Test fun anyFailureAfterLeavingTheAppSaysToKeepItOpen() {
        assertEquals(keepOpen, WriteFailureMessage.export("Clip", generic, ExportOptions.Format.VIDEO, leftForeground = true))
    }

    @Test fun aFailureThatStayedOnScreenIsTheUsualMessage() {
        assertEquals(
            "Couldn't export “Clip”. The video couldn't be written. Try again.",
            WriteFailureMessage.export("Clip", generic, ExportOptions.Format.VIDEO, leftForeground = false),
        )
    }

    /** A full disk is a full disk wherever the app was. */
    @Test fun aNamedCauseWinsOverLeavingTheApp() {
        val full = IOException("ENOSPC (No space left on device)", generic)
        assertEquals(
            "Couldn't export “Clip”. There isn't enough free space to write the video. Try again.",
            WriteFailureMessage.export("Clip", full, ExportOptions.Format.VIDEO, leftForeground = true),
        )
    }

    /** A WAV renders on the CPU and carries on in the background. */
    @Test fun aWavIsNeverToldToKeepTheAppOpen() {
        assertEquals(
            "Couldn't export “Clip”. The WAV file couldn't be written. Try again.",
            WriteFailureMessage.export("Clip", generic, ExportOptions.Format.WAV, leftForeground = true),
        )
    }
}

/** A fake that records what the studio asked of it. */
class RecordingKeepAlive : ExportKeepAlive {
    var begins = 0
    var ends = 0
    var leftForeground = false
    override fun begin() { begins += 1 }
    override fun end(): Boolean { ends += 1; return leftForeground }
}

/** Port of iOS's `StudioExportKeepAliveTests`: the studio keeps the screen on
 * for the length of a video render, and lets go however the render ends. */
class StudioExportKeepAliveTest {
    private val harnesses = ArrayList<StudioHarness>()

    private fun make(result: ExportResult, keepAlive: RecordingKeepAlive): StudioHarness =
        StudioHarness(renderer = { _: ExportRequest -> result }, keepAlive = keepAlive).also { harnesses.add(it) }

    @After fun tearDown() = harnesses.forEach { it.close() }

    private val video = ExportOptions(format = ExportOptions.Format.VIDEO)

    @Test fun aVideoRenderIsKeptAliveAndLetGoOnEveryEnding() {
        val endings = listOf(
            "success" to ExportResult.Success(File(System.getProperty("java.io.tmpdir"), "keep.mp4")),
            "canceled" to ExportResult.Canceled,
            "tooLong" to ExportResult.TooLong,
            "failed" to ExportResult.Failed(IOException("x")),
        )
        for ((name, result) in endings) {
            val keepAlive = RecordingKeepAlive()
            val h = make(result, keepAlive)
            h.studio.export(video)
            assertEquals("$name: kept alive while rendering", 1, keepAlive.begins)
            assertEquals("$name: let go too early", 0, keepAlive.ends)
            h.waitForExport()
            assertEquals("$name: let go once it ended", 1, keepAlive.ends)
        }
    }

    @Test fun aWavRenderIsLeftAlone() {
        val keepAlive = RecordingKeepAlive()
        val h = make(ExportResult.Canceled, keepAlive)
        h.studio.export()
        h.waitForExport()
        assertEquals(0, keepAlive.begins)
        assertEquals(0, keepAlive.ends)
    }

    @Test fun aVideoThatFailedAfterLeavingTheAppSaysToKeepItOpen() {
        val keepAlive = RecordingKeepAlive().apply { leftForeground = true }
        val h = make(ExportResult.Failed(IllegalStateException("codec")), keepAlive)
        h.studio.export(video)
        h.waitForExport()
        val error = h.studio.exportError
        assertTrue("$error", error?.endsWith("Keep Chiptune open while the video renders.") == true)
    }
}
