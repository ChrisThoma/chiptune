package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.Song
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of iOS's `ExportFormatTests`: the WAV / MIDI choice rides in the
 * options, and one dispatcher turns it into the writer that runs. */
class ExportFormatTest {

    @get:Rule val temp = TemporaryFolder()

    private fun song(): Song = TestSongs.empty(name = "Format", tempo = 240.0, length = 4).setNote(0, 0, 60)

    private fun render(song: Song, options: ExportOptions = ExportOptions()): ExportResult =
        ExportRenderer.render(ExportRequest(song, options), temp.root)

    private fun file(result: ExportResult): File {
        if (result !is ExportResult.Success) fail("export did not succeed: $result")
        return (result as ExportResult.Success).file
    }

    @Test fun optionsDefaultToWav() {
        assertEquals(ExportOptions.Format.WAV, ExportOptions().format)
    }

    /** Everything that names a format or its file reads it from here, so the
     * extension, the alert's noun, the sheet's label and the MIME type can't
     * drift apart. */
    @Test fun eachFormatNamesItsFile() {
        assertEquals("wav", ExportOptions.Format.WAV.fileExtension)
        assertEquals("mid", ExportOptions.Format.MIDI.fileExtension)
        assertEquals("WAV file", ExportOptions.Format.WAV.fileNoun)
        assertEquals("MIDI file", ExportOptions.Format.MIDI.fileNoun)
        assertEquals("WAV", ExportOptions.Format.WAV.label)
        assertEquals("MIDI", ExportOptions.Format.MIDI.label)
        assertEquals("audio/wav", ExportOptions.Format.WAV.mimeType)
        assertEquals("audio/midi", ExportOptions.Format.MIDI.mimeType)
    }

    @Test fun aFormatIsFoundFromItsExtensionInAnyCase() {
        assertEquals(ExportOptions.Format.WAV, ExportOptions.Format.fromExtension("wav"))
        assertEquals(ExportOptions.Format.WAV, ExportOptions.Format.fromExtension("WAV"))
        assertEquals(ExportOptions.Format.MIDI, ExportOptions.Format.fromExtension("mid"))
        assertEquals(ExportOptions.Format.MIDI, ExportOptions.Format.fromExtension("Mid"))
        assertEquals(null, ExportOptions.Format.fromExtension("chipsong"))
        assertEquals(null, ExportOptions.Format.fromExtension("midi"))
        assertEquals(null, ExportOptions.Format.fromExtension(""))
    }

    /** Tests build options positionally, so format has to come after the rest. */
    @Test fun formatIsTheLastConstructorParameter() {
        val options = ExportOptions(3, ExportOptions.TailMode.RING_OUT, ExportOptions.Format.MIDI)
        assertEquals(3, options.loopCount)
        assertEquals(ExportOptions.TailMode.RING_OUT, options.tailMode)
        assertEquals(ExportOptions.Format.MIDI, options.format)
    }

    @Test fun wavFormatRendersAWavFile() {
        assertEquals("wav", file(render(song())).extension)
    }

    @Test fun midiFormatRendersAMidFile() {
        val written = file(render(song(), ExportOptions(format = ExportOptions.Format.MIDI)))
        assertEquals("mid", written.extension)
        assertTrue(written.exists())
    }

    /** The WAV size limit is a RIFF constraint; a MIDI file of the longest
     * arrangement and the most repeats is still a few kilobytes. */
    @Test fun midiNeverReportsTooLong() {
        val slow = song().copy(tempo = 30.0)
        val options = ExportOptions(ExportOptions.MAX_LOOP_COUNT, ExportOptions.TailMode.RING_OUT, ExportOptions.Format.MIDI)
        assertFalse(render(slow, options) is ExportResult.TooLong)
    }
}
