package dev.individuation.chiptune.ui.editor

import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import org.junit.Assert.assertEquals
import org.junit.Test

class SongTitleFieldTest {
    /** A song title is a made-up name; autocorrect would rewrite it as it is
     * typed, as iOS stopped doing. */
    @Test fun theTitleIsNotAutocorrected() {
        val options = SongTitleField.keyboardOptions
        assertEquals(false, options.autoCorrectEnabled)
        assertEquals(KeyboardCapitalization.Words, options.capitalization)
        assertEquals(ImeAction.Done, options.imeAction)
    }
}
