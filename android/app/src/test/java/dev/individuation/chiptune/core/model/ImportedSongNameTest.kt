package dev.individuation.chiptune.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

/** Port of `ImportedSongNameTests.swift` (the store case waits for SongStore in Phase 3). */
class ImportedSongNameTest {

    private fun importedName(name: String): String {
        val song = Song.create("Placeholder").copy(name = name)
        return SongDocument.decode(SongDocument.encode(song).toByteArray()).name
    }

    @Test fun whitespaceOnlyNameFallsBackToUntitled() = assertEquals("Untitled", importedName("   "))

    @Test fun emptyNameFallsBackToUntitled() = assertEquals("Untitled", importedName(""))

    @Test fun paddedNameIsTrimmedAndKeepsInternalSpacing() =
        assertEquals("Boss  Door", importedName("  Boss  Door  "))

    @Test fun normalNameIsUnchanged() = assertEquals("Boss Door", importedName("Boss Door"))

    @Test fun nonAsciiAndEscapesSurvive() =
        assertEquals("歌 \"q\" \\ 🎵\tx", importedName("歌 \"q\" \\ 🎵\tx"))
}
