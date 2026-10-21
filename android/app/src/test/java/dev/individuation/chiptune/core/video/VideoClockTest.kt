package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.ui.layout.Format
import org.junit.Assert.assertEquals
import org.junit.Test

/** The times a Cartridge video draws. The total is the Export sheet's own
 * text, and the running clock is drawn in the same shape as the total: with
 * a tenth when the total has one, whole seconds otherwise. It is truncated,
 * so it never runs ahead of the audio, and the last frame shows the total. */
class VideoClockTest {

    @Test fun theTotalIsTheExportSheetsText() {
        for (seconds in listOf(0.0, 0.04, 0.05, 1.8, 4.1, 4.14, 9.94, 9.96, 10.0, 59.5, 67.4, 599.9)) {
            assertEquals("total of $seconds", Format.clock(seconds), VideoClock.total(seconds))
        }
        assertEquals("0:04.1", VideoClock.total(4.1))
        assertEquals("1:07", VideoClock.total(67.4))
    }

    /** iOS showed "0:00" against "0:04.1"; the two now share a shape. */
    @Test fun aShortSongsRunningClockKeepsTheTotalsTenths() {
        assertEquals("0:00.0", VideoClock.elapsed(0.0, total = 4.1, isFinalFrame = false))
        assertEquals("0:02.0", VideoClock.elapsed(2.0, total = 4.1, isFinalFrame = false))
        assertEquals("0:04.0", VideoClock.elapsed(4.09, total = 4.1, isFinalFrame = false))
        assertEquals("0:04.1", VideoClock.elapsed(4.1, total = 4.1, isFinalFrame = true))
    }

    @Test fun theRunningClockTruncatesSoItNeverRunsAhead() {
        assertEquals("0:01.7", VideoClock.elapsed(1.79, total = 4.1, isFinalFrame = false))
        // A frame's time in samples, a hair under the tenth in binary.
        assertEquals("0:00.3", VideoClock.elapsed(13230.0 / 44100.0, total = 4.1, isFinalFrame = false))
        assertEquals("0:59", VideoClock.elapsed(59.99, total = 67.4, isFinalFrame = false))
    }

    @Test fun aLongerSongsRunningClockCountsWholeSeconds() {
        assertEquals("0:00", VideoClock.elapsed(0.0, total = 67.4, isFinalFrame = false))
        assertEquals("1:05", VideoClock.elapsed(65.7, total = 67.4, isFinalFrame = false))
        // 9.96 s reads "0:10" on the sheet, so the clock counts whole seconds.
        assertEquals("0:09", VideoClock.elapsed(9.9, total = 9.96, isFinalFrame = false))
    }

    @Test fun theLastFrameShowsTheTotal() {
        assertEquals("1:07", VideoClock.elapsed(67.3, total = 67.4, isFinalFrame = true))
        assertEquals("0:10", VideoClock.elapsed(9.9, total = 9.96, isFinalFrame = true))
    }

    @Test fun theRunningClockNeverShowsMoreThanTheTotal() {
        assertEquals("0:04.1", VideoClock.elapsed(9.0, total = 4.1, isFinalFrame = false))
        assertEquals("0:00.0", VideoClock.elapsed(-1.0, total = 4.1, isFinalFrame = false))
    }
}
