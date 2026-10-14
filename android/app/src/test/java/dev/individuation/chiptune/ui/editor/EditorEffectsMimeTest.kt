package dev.individuation.chiptune.ui.editor

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

/** The MIME type a share or save offers follows the file's extension, not the
 * sheet's current format, which may have been switched since the export finished. */
class EditorEffectsMimeTest {
    @Test fun exportsAreOfferedByTheirExtension() {
        assertEquals("audio/wav", EditorEffects.mimeTypeFor(File("/x/Song.wav")))
        assertEquals("audio/midi", EditorEffects.mimeTypeFor(File("/x/Song.mid")))
        assertEquals("audio/midi", EditorEffects.mimeTypeFor(File("/x/Song.MID")))
    }

    @Test fun anythingElseIsASongFile() {
        assertEquals("application/json", EditorEffects.mimeTypeFor(File("/x/Song.chipsong")))
        assertEquals(EditorEffects.SONG_MIME, EditorEffects.mimeTypeFor(File("/x/Song")))
    }
}
