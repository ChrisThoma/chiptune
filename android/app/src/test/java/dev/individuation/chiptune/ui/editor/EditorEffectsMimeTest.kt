package dev.individuation.chiptune.ui.editor

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

/** The MIME type a share or save offers follows the file's extension, not the
 * sheet's current format, which may have been switched since the export finished. */
class EditorEffectsMimeTest {
    @Test fun midiHasItsOwnType() = assertEquals("audio/midi", EditorEffects.MIDI_MIME)

    @Test fun exportsAreOfferedByTheirExtension() {
        assertEquals(EditorEffects.WAV_MIME, EditorEffects.mimeTypeFor(File("/x/Song.wav")))
        assertEquals(EditorEffects.MIDI_MIME, EditorEffects.mimeTypeFor(File("/x/Song.mid")))
        assertEquals(EditorEffects.MIDI_MIME, EditorEffects.mimeTypeFor(File("/x/Song.MID")))
    }

    @Test fun anythingElseIsASongFile() {
        assertEquals(EditorEffects.SONG_MIME, EditorEffects.mimeTypeFor(File("/x/Song.chipsong")))
        assertEquals(EditorEffects.SONG_MIME, EditorEffects.mimeTypeFor(File("/x/Song")))
    }
}
