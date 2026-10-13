package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.audio.MidiExport
import dev.individuation.chiptune.core.audio.WavExport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ExportFileNameAgreementTests.swift`: one song maps to one safe
 * file base name. The WAV export reuses `SongDocument.safeName` (Phase 2),
 * so the song-file base is what is pinned here. */
class ExportFileNameAgreementTest {
    private fun base(name: String) = SongDocument.safeName(Song.create(name))

    @Test fun slashTitle() = assertEquals("My Song v2", base("My Song / v2"))

    @Test fun repeatedSpacesAndDots() = assertEquals("ab c d", base("  a..b   c . d  "))

    @Test fun emojiOnlyFallsBack() = assertEquals("chiptune", base("🎵🎶"))

    @Test fun blankFallsBack() = assertEquals("chiptune", base("   "))

    /** The WAV and MIDI writers name their files from the same safe base as the song file. */
    private fun exportBases(name: String): Pair<String, String> {
        val song = Song.create(name)
        val dir = java.io.File(System.getProperty("java.io.tmpdir"), "chiptune-names-${java.util.UUID.randomUUID()}")
        try {
            return WavExport.filename(song, dir).nameWithoutExtension to MidiExport.filename(song, dir).nameWithoutExtension
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun midiAndWavNamesAgreeWithTheSongName() {
        for (name in listOf("My Song / v2", "  a..b   c . d  ", "🎵🎶", "   ", "L".repeat(300), "歌".repeat(90))) {
            val (wav, mid) = exportBases(name)
            assertEquals(name, base(name), wav)
            assertEquals(name, base(name), mid)
        }
        assertEquals("chiptune", exportBases("🎵🎶").second)
        assertEquals("My Song v2", exportBases("My Song / v2").second)
    }

    @Test fun midiFileEndsInMid() {
        val song = Song.create("Neon")
        val dir = java.io.File(System.getProperty("java.io.tmpdir"), "chiptune-names-${java.util.UUID.randomUUID()}")
        try {
            assertEquals("Neon.mid", MidiExport.filename(song, dir).name)
        } finally {
            dir.deleteRecursively()
        }
    }

    /** `CharacterSet.alphanumerics` is letters, marks and numbers in any script. */
    @Test fun lettersMarksAndNumbersInAnyScriptSurvive() {
        assertEquals("Café 歌 ٣ e\u0301", base("Café 歌 ٣ e\u0301!"))
        assertEquals("a-b_c", base("a-b_c"))
        assertEquals("ab", base("a\tb"))
    }
}

/** Port of `LongSongNameFileTests.swift`. */
class LongSongNameFileTest {
    private fun assertFits(fileName: String, ext: String) {
        val bytes = fileName.toByteArray(Charsets.UTF_8).size
        assertTrue("$bytes bytes", bytes <= 255)
        assertTrue(fileName.endsWith(".$ext"))
        assertTrue(bytes > ext.length + 1)
    }

    @Test fun songFileNameSurvivesA300CharacterName() {
        val song = Song.create("L".repeat(300))
        assertFits(SongDocument.fileName(song), SongDocument.FILE_EXTENSION)
        assertEquals(200, SongDocument.safeName(song).length)
        assertEquals(300, song.name.length)
    }

    @Test fun songFileNameSurvivesAnOverLongCJKName() {
        val song = Song.create("歌".repeat(90))
        assertFits(SongDocument.fileName(song), SongDocument.FILE_EXTENSION)
        // Three bytes each: 66 fit in 200 bytes, and none is split.
        assertEquals("歌".repeat(66), SongDocument.safeName(song))
    }

    @Test fun songFileNormalNameIsUnchanged() =
        assertEquals("My Song.chipsong", SongDocument.fileName(Song.create("My Song")))

    @Test fun truncationNeverSplitsAGraphemeAndDropsATrailingSpace() {
        // 199 ASCII bytes then a space and an accented letter: the cut lands
        // after the space, which is then trimmed.
        assertEquals("a".repeat(199), SongDocument.truncatedForFileName("a".repeat(199) + " é"))
        // e + combining acute is one character of 3 bytes; it must not be split.
        assertEquals("a".repeat(198), SongDocument.truncatedForFileName("a".repeat(198) + "e\u0301"))
        assertEquals("short", SongDocument.truncatedForFileName("short"))
    }
}
