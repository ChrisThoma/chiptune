package dev.individuation.chiptune.ui.editor

import org.junit.Assert.assertEquals
import org.junit.Test

/** The menu's links are the same pages the Play listing declares: Play
 * requires the in-app privacy policy to be the one on the store listing. */
class EditorEffectsLinksTest {
    @Test fun privacyPolicyIsTheListingsPolicy() =
        assertEquals("https://individuation.dev/projects/chiptune/privacy.html", EditorEffects.PRIVACY_URL)

    @Test fun supportIsTheContactPage() =
        assertEquals("https://individuation.dev/contact/", EditorEffects.SUPPORT_URL)
}
