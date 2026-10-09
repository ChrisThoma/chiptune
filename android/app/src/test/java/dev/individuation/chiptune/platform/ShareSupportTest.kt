package dev.individuation.chiptune.platform

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.studio.ShareOutcome
import dev.individuation.chiptune.core.studio.SongShareWriter
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareSupportTest {
    @Test fun chosenTargetCompletesAndNoTargetCancels() {
        assertEquals(ShareOutcome.COMPLETED, ShareResult.outcome("com.example/.Share"))
        assertEquals(ShareOutcome.CANCELED, ShareResult.outcome(null))
        assertEquals(ShareOutcome.CANCELED, ShareResult.outcome(""))
    }

    @Test fun shareAndExportFilesLieUnderProviderRoots() {
        val cache = Files.createTempDirectory("cache").toFile()
        val song = TestSongs.empty()
        val shared = SongShareWriter(File(cache, ShareRoots.SHARE)).write(song)
        val wav = WavExport.filename(song, File(cache, ShareRoots.EXPORT)).also { it.writeText("x") }
        assertTrue(ShareRoots.covers(cache, shared))
        assertTrue(ShareRoots.covers(cache, wav))
    }

    @Test fun otherCacheFilesAreNotExposed() {
        val cache = Files.createTempDirectory("cache").toFile()
        assertFalse(ShareRoots.covers(cache, File(cache, "secret.txt")))
        assertFalse(ShareRoots.covers(cache, File(cache, "share/../secret.txt")))
        assertFalse(ShareRoots.covers(cache, File(cache, "shared-evil/a")))
        assertFalse(ShareRoots.covers(cache, File(cache.parentFile, "elsewhere/a")))
    }
}
