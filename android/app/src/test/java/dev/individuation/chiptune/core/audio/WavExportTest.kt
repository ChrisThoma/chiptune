package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.SongSection
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of `WavExportTests.swift`: the file must be a spec-valid 44.1 kHz
 * 16-bit mono WAV, exactly one arrangement pass long, with the final notes'
 * ring-out folded over its start. Read back with a generic RIFF walk. */
class WavExportTest {

    @get:Rule val temp = TemporaryFolder()

    private fun expectedDuration(steps: Int, tempo: Double): Double = steps * 60.0 / (tempo * 4.0)

    private fun export(song: dev.individuation.chiptune.core.model.Song): File {
        val file = WavExport.render(song, temp.root)
        assertNotNull("export failed", file)
        return file!!
    }

    // MARK: Format

    @Test fun exportedFileIsValidWavWithDeclaredFormat() {
        val song = TestSongs.empty(tempo = 120.0).setNote(0, 0, 60).setNote(2, 8, 48)
        val file = export(song)
        val format = WavFile.format(file)
        assertEquals(44100, format.sampleRate)
        assertEquals(1, format.channels)
        assertEquals(16, format.bitsPerSample)
        assertEquals(1, format.formatTag)
        val seconds = WavFile.pcm16(file).size / 44100.0
        assertEquals(expectedDuration(16, 120.0), seconds, 0.01)
    }

    @Test fun riffStructureIsInternallyConsistent() {
        val data = export(TestSongs.empty(tempo = 240.0).setNote(0, 0, 72)).readBytes()
        assertTrue(data.size > 12)
        assertEquals("RIFF", String(data, 0, 4, Charsets.US_ASCII))
        assertEquals("WAVE", String(data, 8, 4, Charsets.US_ASCII))
        assertEquals("RIFF size must cover the rest of the file", data.size - 8, WavFile.le32(data, 4))

        var offset = 12
        var sawFmt = false
        var sawData = false
        while (offset + 8 <= data.size) {
            val id = String(data, offset, 4, Charsets.US_ASCII)
            val size = WavFile.le32(data, offset + 4)
            assertTrue("chunk '$id' overruns the file", offset + 8 + size <= data.size)
            if (id == "fmt ") {
                sawFmt = true
                assertEquals(16, size)
                assertEquals("byte rate", 88200, WavFile.le32(data, offset + 16))
                assertEquals("block align", 2, WavFile.le16(data, offset + 20))
            }
            if (id == "data") {
                sawData = true
                assertEquals("data chunk must run exactly to end of file", data.size, offset + 8 + size)
            }
            offset += 8 + size + (size % 2)
        }
        assertTrue("missing fmt chunk", sawFmt)
        assertTrue("missing data chunk", sawData)
        assertEquals("canonical 44-byte header", 44, data.size - WavFile.pcm16(data).size * 2)
    }

    // MARK: Loop semantics

    @Test fun finalNoteRingsIntoTheStartAndFileEndsHot() {
        val song = TestSongs.empty(tempo = 120.0)
            .withInstrument(0) { it.copy(decay = 2.0, volume = 0.8) }
            .setNote(0, 15, 72)
        val samples = WavFile.samples(export(song))
        val sr = 44100
        assertFalse("export contains NaN samples", samples.any { it.isNaN() })
        val start = RenderHarness.rms(samples, 0, sr / 10)
        val middle = RenderHarness.rms(samples, sr + sr / 5, sr + sr / 2)
        val end = RenderHarness.rms(samples, samples.size - sr / 10, samples.size)
        assertTrue("the last note should still be ringing when the file ends", end > 0.001)
        assertTrue("the ring-out past the end should be folded over the file's start", start > 0.001)
        assertTrue("a 3.0 s tail wrapping a 2.0 s head rings through the middle too", middle > 0.001)
    }

    @Test fun seamlessFoldReachesPastTheOldOneSecondBoundary() {
        val song = TestSongs.empty(tempo = 120.0, length = 64)
            .withInstrument(0) { it.copy(decay = 2.0, volume = 0.9) }
            .setNote(0, 63, 72)
        val samples = WavFile.samples(export(song))
        val sr = 44100
        val window = RenderHarness.rms(samples, sr + sr / 5, sr + 2 * sr / 5)
        assertTrue("a tail scaled to the decay should still be ringing 1.2 s in", window > 0.001)
    }

    @Test fun songShorterThanRingOutStillExports() {
        val song = TestSongs.empty(tempo = 300.0, length = 4)
            .withInstrument(0) { it.copy(decay = 2.0) }
            .setNote(0, 3, 72)
        val samples = WavFile.samples(export(song))
        assertEquals(expectedDuration(4, 300.0), samples.size / 44100.0, 0.01)
        assertFalse(samples.any { it.isNaN() })
        assertTrue("the wrapped ring-out should leave audible content", RenderHarness.rms(samples) > 0.001)
        assertTrue("folded overlap must not exceed full scale", RenderHarness.peak(samples) <= 1.0)
    }

    /** A loud ring-out folded over a loud start sums past full scale; the
     * whole file is scaled down rather than the seam being clipped. Beyond
     * Swift's suite, which never drives the fold that hot. */
    @Test fun aFoldPastFullScaleIsScaledRatherThanClipped() {
        var song = TestSongs.empty(tempo = 300.0, length = 4)
        for (t in 0 until 3) {
            song = song.withInstrument(t) { it.copy(decay = 4.0, volume = 1.0, duty = 2) }
                .setNote(t, 0, 48 + t * 7).setNote(t, 3, 48 + t * 7)
        }
        val ints = WavFile.pcm16(export(song))
        val peak = ints.maxOf { kotlin.math.abs(it.toInt()) }
        val pinned = ints.count { kotlin.math.abs(it.toInt()) >= 32760 }
        println("fold peak $peak, samples at full scale $pinned")
        assertTrue("the file should be normalized to full scale (peak $peak)", peak >= 32000)
        assertTrue("$pinned samples are pinned at full scale: the seam was clipped, not scaled", pinned <= 2)
    }

    // MARK: Filenames

    @Test fun sameNamedSongsDoNotOverwriteEachOther() {
        val silent = TestSongs.empty(name = "Twin", tempo = 240.0)
        val loud = TestSongs.empty(name = "Twin", tempo = 240.0)
            .withInstrument(0) { it.copy(sustain = true) }.setNote(0, 0, 72)
        val silentFile = export(silent)
        val loudFile = export(loud)
        assertNotEquals("two songs with the same name must not share an export path", silentFile, loudFile)
        assertTrue(silentFile.exists())
        assertTrue("the silent song's export was overwritten", RenderHarness.rms(WavFile.samples(silentFile)) < 0.0005)
        assertTrue(RenderHarness.rms(WavFile.samples(loudFile)) > 0.001)
    }

    /** `tmp/<SONG-UUID>/<safeName>.wav`, with Swift's uppercase `uuidString`. */
    @Test fun theExportLivesInAPerSongFolderNamedAfterTheSong() {
        val song = TestSongs.empty(name = "My Song!", tempo = 240.0)
        val file = export(song)
        assertEquals("My Song.wav", file.name)
        assertEquals(song.id.toString().uppercase(), file.parentFile.name)
        assertEquals(temp.root.canonicalFile, file.parentFile.parentFile.canonicalFile)
        assertEquals(file, WavExport.filename(song, temp.root))
    }

    // MARK: Pruning

    @Test fun renamingASongReplacesItsOldExportRatherThanAccumulating() {
        var song = TestSongs.empty(name = "One", tempo = 240.0)
            .withInstrument(0) { it.copy(sustain = true) }.setNote(0, 0, 60)
        val first = export(song)
        assertTrue(first.exists())
        song = song.copy(name = "Two")
        val second = export(song)
        val contents = first.parentFile.list()!!.filter { it.endsWith(".wav") }.toSet()
        assertEquals(setOf("Two.wav"), contents)
        assertFalse("the stale export should have been pruned", first.exists())
        assertTrue(second.exists())
    }

    @Test fun failedRerenderPreservesThePreviousExport() {
        var song = TestSongs.empty(name = "One", tempo = 240.0)
            .withInstrument(0) { it.copy(sustain = true) }.setNote(0, 0, 60)
        val first = export(song)
        val firstBytes = first.readBytes()

        song = song.copy(
            name = "Two",
            tempo = Chip.TEMPO_MIN,
            patterns = song.patterns.map { it.copy(length = Chip.MAX_STEPS) },
        )
        song = song.copy(arrangement = List(8) { SongSection(patternID = song.patterns[0].id, repeats = SongSection.MAX_REPEATS) })
        val result = WavExport.render(ExportRequest(song, ExportOptions(loopCount = ExportOptions.MAX_LOOP_COUNT)), temp.root)
        assertEquals(ExportResult.TooLong, result)
        assertTrue("a failed rerender must not touch the previous export", first.exists())
        assertArrayEquals(firstBytes, first.readBytes())
    }

    // MARK: Failure (port-specific: the root is injectable, so it can be made unusable)

    @Test fun anUnwritableRootFailsRatherThanThrowing() {
        val notADirectory = temp.newFile("plain-file")
        val result = WavExport.render(ExportRequest(TestSongs.empty().setNote(0, 0, 60)), notADirectory)
        assertTrue("expected Failed, got $result", result is ExportResult.Failed)
    }

    // MARK: Sample conversion

    /** `Int16(Float)` truncates toward zero; so must the port. */
    @Test fun pcmConversionTruncatesTowardZeroAndClamps() {
        assertEquals(32766.toShort(), WavExport.pcm16(0.99999f, 1f)) // 32766.67 -> 32766
        assertEquals((-16383).toShort(), WavExport.pcm16(-0.5f, 1f)) // -16383.5 -> -16383
        assertEquals(32767.toShort(), WavExport.pcm16(3f, 1f))
        assertEquals((-32767).toShort(), WavExport.pcm16(-3f, 1f))
        assertEquals(16383.toShort(), WavExport.pcm16(1f, 0.5f))
        assertEquals(0.toShort(), WavExport.pcm16(0.00003f, 1f)) // 0.98 -> 0
    }
}
