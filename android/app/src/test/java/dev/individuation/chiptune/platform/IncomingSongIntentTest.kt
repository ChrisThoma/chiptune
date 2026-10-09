package dev.individuation.chiptune.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingSongIntentTest {
    private val view = "android.intent.action.VIEW"
    private val send = "android.intent.action.SEND"

    @Test fun viewWithDataUriIsAccepted() {
        val r = IncomingSongIntent.parse(view, "content://x/1", null, "application/json")
        assertEquals(IncomingSongIntent.Result.Accepted("content://x/1"), r)
    }

    @Test fun viewWithoutTypeIsAccepted() {
        assertEquals(
            IncomingSongIntent.Result.Accepted("file:///a.chipsong"),
            IncomingSongIntent.parse(view, "file:///a.chipsong", null, null),
        )
    }

    @Test fun sendUsesStreamExtra() {
        val r = IncomingSongIntent.parse(send, null, "content://x/2", "application/octet-stream")
        assertEquals(IncomingSongIntent.Result.Accepted("content://x/2"), r)
    }

    @Test fun sendIgnoresDataAndNeedsStream() {
        assertEquals(
            IncomingSongIntent.Result.Rejected(IncomingSongIntent.Reason.NO_URI),
            IncomingSongIntent.parse(send, "content://x/3", null, "application/json"),
        )
    }

    @Test fun otherActionsAreRejected() {
        assertEquals(
            IncomingSongIntent.Result.Rejected(IncomingSongIntent.Reason.WRONG_ACTION),
            IncomingSongIntent.parse("android.intent.action.MAIN", "content://x/1", null, null),
        )
        assertEquals(
            IncomingSongIntent.Result.Rejected(IncomingSongIntent.Reason.WRONG_ACTION),
            IncomingSongIntent.parse(null, "content://x/1", null, null),
        )
    }

    @Test fun missingOrBlankUriIsRejected() {
        val none = IncomingSongIntent.Result.Rejected(IncomingSongIntent.Reason.NO_URI)
        assertEquals(none, IncomingSongIntent.parse(view, null, null, "application/json"))
        assertEquals(none, IncomingSongIntent.parse(view, "  ", null, "application/json"))
    }

    @Test fun wrongTypeIsRejected() {
        assertEquals(
            IncomingSongIntent.Result.Rejected(IncomingSongIntent.Reason.WRONG_TYPE),
            IncomingSongIntent.parse(view, "content://x/1", null, "image/png"),
        )
    }
}

class SongFileAcceptanceTest {
    @Test fun acceptsSongExtensionsInAnyCase() {
        assertTrue(SongFileAcceptance.accepts("Tune.chipsong", null))
        assertTrue(SongFileAcceptance.accepts("TUNE.CHIPSONG", "application/octet-stream"))
        assertTrue(SongFileAcceptance.accepts("tune.JSON", "text/plain"))
    }

    @Test fun rejectsOtherNames() {
        assertFalse(SongFileAcceptance.accepts("notes.txt", "application/json"))
        assertFalse(SongFileAcceptance.accepts("tune.chipsong.zip", "application/json"))
        assertFalse(SongFileAcceptance.accepts("tune", "application/json"))
    }

    @Test fun unknownNameNeedsJsonMime() {
        assertTrue(SongFileAcceptance.accepts(null, "application/json"))
        assertTrue(SongFileAcceptance.accepts("  ", "application/json"))
        assertFalse(SongFileAcceptance.accepts(null, "application/octet-stream"))
        assertFalse(SongFileAcceptance.accepts(null, null))
    }

    @Test fun sizeCap() {
        assertTrue(SongFileAcceptance.fitsSizeCap(10L * 1024 * 1024))
        assertFalse(SongFileAcceptance.fitsSizeCap(10L * 1024 * 1024 + 1))
    }

    @Test fun dropMimeRule() {
        assertTrue(SongFileAcceptance.acceptsDropMime("application/json"))
        assertTrue(SongFileAcceptance.acceptsDropMime("application/octet-stream"))
        assertTrue(SongFileAcceptance.acceptsDropMime("text/uri-list"))
        assertFalse(SongFileAcceptance.acceptsDropMime("image/png"))
    }
}
