package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.model.SongDecodeException
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.file.AccessDeniedException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Stands in for `android.system.ErrnoException`, which core can't import:
 * matched by simple name and message, as the classifier does. */
private class ErrnoException(message: String) : Exception(message)

/** Port of `ShareFailureMessageTests.swift` (all its suites) and
 * `AudioFailureMessageTests.swift`, with Java/Android exceptions standing in
 * for the Cocoa and POSIX codes. */
class FailureMessageTest {

    private val permission: Throwable = AccessDeniedException("/data/user/0/app/files/Songs/0C1D.json")
    private val space: Throwable = IOException("write failed: ENOSPC (No space left on device)")
    private val other: Throwable = IOException("raw system text in the folder \u201Cshare-ABC\u201D")

    // MARK: Cause

    @Test fun permissionCausesAreRecognized() {
        val cases = listOf(
            AccessDeniedException("x"),
            SecurityException("Permission Denial"),
            FileNotFoundException("/x/y.json: open failed: EACCES (Permission denied)"),
            FileNotFoundException("/x/y.json (Permission denied)"),
            IOException("EPERM (Operation not permitted)"),
            ErrnoException("open failed: EACCES (Permission denied)"),
        )
        for (e in cases) assertEquals("$e", WriteFailureMessage.Cause.PERMISSION, WriteFailureMessage.cause(e))
    }

    @Test fun spaceCausesAreRecognized() {
        val cases = listOf(
            IOException("write failed: ENOSPC (No space left on device)"),
            IOException("No space left on device"),
            ErrnoException("write failed: ENOSPC"),
        )
        for (e in cases) assertEquals("$e", WriteFailureMessage.Cause.SPACE, WriteFailureMessage.cause(e))
    }

    @Test fun anUnderlyingCauseIsNamed() {
        val full = IOException("generic write error", ErrnoException("write failed: ENOSPC (No space left on device)"))
        val denied = IOException("generic write error", AccessDeniedException("x"))
        assertEquals("There isn't enough free space to write the WAV file.", WriteFailureMessage.reason(full, "WAV file"))
        assertEquals("The app doesn't have permission to write the WAV file.", WriteFailureMessage.reason(denied, "WAV file"))
    }

    @Test fun anUnknownCauseSaysSoPlainly() {
        assertEquals("The WAV file couldn't be written.", WriteFailureMessage.reason(IOException("boom"), "WAV file"))
        assertEquals(WriteFailureMessage.Cause.OTHER, WriteFailureMessage.cause(IllegalStateException()))
    }

    @Test fun aCyclicCauseChainEnds() {
        val a = IOException("a")
        val b = IOException("b", a)
        a.initCause(b)
        assertEquals(WriteFailureMessage.Cause.OTHER, WriteFailureMessage.cause(a))
    }

    // MARK: Share failed

    @Test fun longNameIsClippedWithEllipsisAndAppearsOnce() {
        val name = "N".repeat(300)
        val msg = ShareFailureMessage.songFile(name, other)
        assertFalse(msg.contains(name))
        assertTrue(msg.contains("\u2026"))
        assertTrue(msg.length < 140)
    }

    @Test fun shortNameIsUntouched() {
        val msg = ShareFailureMessage.songFile("Neon Ascent", other)
        assertTrue(msg.contains("\u201CNeon Ascent\u201D"))
        assertFalse(msg.contains("\u2026"))
    }

    @Test fun rawSystemTextAndFolderNamesAreNotPasted() {
        val msg = ShareFailureMessage.songFile("A", other)
        assertFalse(msg.contains("raw system text"))
        assertFalse(msg.contains("share-"))
        assertTrue(msg.lowercase().contains("try again"))
    }

    @Test fun onlyAPermissionCauseLeavesOffTryAgain() {
        val builders: List<(String, Throwable) -> String> = listOf(
            ShareFailureMessage::songFile, WriteFailureMessage::save, WriteFailureMessage::export,
        )
        for (build in builders) {
            assertFalse(build("A", permission), build("A", permission).contains("Try again"))
            assertTrue(build("A", space), build("A", space).endsWith(" Try again."))
            assertTrue(build("A", other), build("A", other).endsWith(" Try again."))
        }
    }

    @Test fun permissionAndSpaceErrorsGetOneShortClue() {
        val perm = ShareFailureMessage.songFile("A", permission)
        val full = ShareFailureMessage.songFile("A", space)
        val plain = ShareFailureMessage.songFile("A", other)
        assertTrue(perm.lowercase().contains("permission"))
        assertTrue(full.lowercase().contains("space"))
        assertNotEquals(perm, full)
        assertNotEquals(perm, plain)
    }

    @Test fun blankNameStillReadsAsASentence() {
        assertEquals("Couldn't prepare this song to share. The song file couldn't be written. Try again.",
            ShareFailureMessage.songFile("  ", other))
    }

    @Test fun theSheetsOwnFailureNamesTheFileAndNothingRaw() {
        assertEquals("Couldn't share the song file. Try again.", ShareFailureMessage.sheet("song file"))
        assertEquals("Couldn't share the WAV file. Try again.", ShareFailureMessage.sheet("WAV file"))
    }

    // MARK: Save failed

    @Test fun saveKeepsTheReasonAndDropsTheRawText() {
        assertEquals("Couldn't save \u201CNeon Ascent\u201D. The app doesn't have permission to write the song file.",
            WriteFailureMessage.save("Neon Ascent", permission))
    }

    @Test fun spaceAndOtherReasonsDiffer() {
        val full = WriteFailureMessage.save("A", space)
        val plain = WriteFailureMessage.save("A", other)
        assertTrue(full.contains("enough free space"))
        assertTrue(plain.contains("couldn't be written"))
        assertFalse(plain.contains(".json"))
    }

    @Test fun saveClipsALongName() {
        val name = "N".repeat(300)
        val msg = WriteFailureMessage.save(name, other)
        assertFalse(msg.contains(name))
        assertTrue(msg.contains("\u2026"))
        assertTrue(msg.length < 140)
    }

    @Test fun theNameClipIsThirtyCharactersTrimmed() {
        assertEquals("\u201C" + "a".repeat(29) + "\u2026\u201D", WriteFailureMessage.shown("a".repeat(29) + " bbbbbbbb"))
        assertEquals("\u201C" + "x".repeat(30) + "\u201D", WriteFailureMessage.shown("x".repeat(30)))
        assertEquals("this song", WriteFailureMessage.shown("\n "))
    }

    @Test fun exportWordsMatchSaveAndShare() {
        assertEquals("Couldn't export \u201CNeon Ascent\u201D. The app doesn't have permission to write the WAV file.",
            WriteFailureMessage.export("Neon Ascent", permission))
    }

    @Test fun exportWordsNameTheFileThatFailed() {
        assertEquals("Couldn't export \u201CNeon Ascent\u201D. The app doesn't have permission to write the MIDI file.",
            WriteFailureMessage.export("Neon Ascent", permission, "MIDI file"))
        assertEquals("MIDI file", WriteFailureMessage.exportFile(ExportOptions.Format.MIDI))
        assertEquals("WAV file", WriteFailureMessage.exportFile(ExportOptions.Format.WAV))
    }

    /** A share or save failure reads the noun off the file that was offered,
     * since the sheet's format may have been switched since the export finished. */
    @Test fun fileNounComesFromTheExtension() {
        assertEquals("MIDI file", WriteFailureMessage.fileNoun("mid"))
        assertEquals("MIDI file", WriteFailureMessage.fileNoun("MID"))
        assertEquals("WAV file", WriteFailureMessage.fileNoun("wav"))
        assertEquals("WAV file", WriteFailureMessage.fileNoun("WAV"))
        assertEquals("song file", WriteFailureMessage.fileNoun("chipsong"))
        assertEquals("song file", WriteFailureMessage.fileNoun(""))
    }

    // MARK: Delete failed

    @Test fun deletePermissionNamesTheCauseWithoutTryAgain() {
        assertEquals("Couldn't delete \u201CDoomed\u201D. The app doesn't have permission to delete the song file.",
            DeleteFailureMessage.song("Doomed", permission))
    }

    @Test fun deleteUnknownCauseSaysTryAgainAndNothingRaw() {
        assertEquals("Couldn't delete \u201CDoomed\u201D. Try again.", DeleteFailureMessage.song("Doomed", other))
        assertEquals("Couldn't delete \u201CDoomed\u201D. Try again.", DeleteFailureMessage.song("Doomed", space))
    }

    // MARK: Import failed

    @Test fun aFileThatIsNotASong() {
        assertEquals("Couldn't import the file. It isn't a Chiptune song, or it's damaged.",
            ImportFailureMessage.file(SongDecodeException("missing \"tracks\"")))
    }

    @Test fun aFileThatCannotBeRead() {
        assertEquals("Couldn't import the file. It couldn't be read. Try again.",
            ImportFailureMessage.file(FileNotFoundException("/x (No such file or directory)")))
        assertEquals("Couldn't import the file. It couldn't be read. Try again.",
            ImportFailureMessage.file(IOException("raw picker text")))
    }

    @Test fun aFileTheAppMayNotRead() {
        assertEquals("Couldn't import the file. The app doesn't have permission to read it.",
            ImportFailureMessage.file(SecurityException("Permission Denial: reading provider")))
    }

    @Test fun aSongThatCannotBeSavedReadsLikeSaveFailed() {
        assertEquals("Couldn't import \u201CNeon Ascent\u201D. There isn't enough free space to write the song file. Try again.",
            ImportFailureMessage.save("Neon Ascent", space))
    }

    // MARK: Audio unavailable

    @Test fun aRefusedFocusSaysAnotherAppHasAudio() {
        assertEquals("Another app or a call is using audio. Try again when it's finished.",
            AudioFailureMessage.start(AudioFocusDeniedException()))
    }

    @Test fun anythingElseIsPlainAndPastesNothing() {
        val plain = "Couldn't start audio. Try again."
        assertEquals(plain, AudioFailureMessage.start(IllegalStateException("AudioTrack init failed: -38")))
        assertEquals(plain, AudioFailureMessage.start(null))
    }
}
