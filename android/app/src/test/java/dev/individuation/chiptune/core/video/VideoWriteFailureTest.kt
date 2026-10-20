package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.studio.WriteFailureMessage
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/** Port of iOS's `VideoWriteFailureCauseTests`. iOS's video writer reports a
 * full disk in its own domain (`AVError.diskFull`); Android's MediaMuxer
 * reports one as a bare IllegalStateException with no errno in it, so the
 * free space left on the volume is what tells a full disk apart. */
class VideoWriteFailureTest {

    private val video = ExportOptions.Format.VIDEO.fileNoun
    private val muxer = IllegalStateException("Failed to stop the muxer")

    @Test fun aMuxerFailureOnAFullVolumeIsASpaceProblem() {
        val explained = VideoWriteFailure.explain(muxer, freeBytes = 200_000)
        assertEquals(WriteFailureMessage.Cause.SPACE, WriteFailureMessage.cause(explained))
        assertEquals(
            "Couldn't export “Clip”. There isn't enough free space to write the video. Try again.",
            WriteFailureMessage.export("Clip", explained, video),
        )
    }

    @Test fun aMuxerFailureWithRoomLeftIsLeftAlone() {
        assertSame(muxer, VideoWriteFailure.explain(muxer, freeBytes = 4_000_000_000))
        assertEquals(WriteFailureMessage.Cause.OTHER, WriteFailureMessage.cause(VideoWriteFailure.explain(muxer, 4_000_000_000)))
    }

    /** A failure that already names its cause keeps it, even on a full disk. */
    @Test fun aFailureWithItsOwnCauseKeepsIt() {
        val denied = SecurityException("Permission Denial")
        assertSame(denied, VideoWriteFailure.explain(denied, freeBytes = 0))
        val full = IOException("write failed: ENOSPC (No space left on device)")
        assertSame(full, VideoWriteFailure.explain(full, freeBytes = 4_000_000_000))
    }
}
