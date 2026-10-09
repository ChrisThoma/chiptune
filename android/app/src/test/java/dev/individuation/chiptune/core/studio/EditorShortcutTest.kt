package dev.individuation.chiptune.core.studio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of `EditorShortcutTests.swift`: the Ctrl chords, checked against the
 * two things that silently break them -- two actions on one chord, and a
 * chord that the note row would read as a note -- plus the guards that keep
 * them from changing the song under a dialog.
 */
class EditorShortcutTest {
    private val ctrl = KeyModifiers(ctrl = true)
    private val ctrlShift = KeyModifiers(ctrl = true, shift = true)

    @Test fun everyChordIsUsedOnce() {
        val seen = mutableMapOf<String, String>()
        for (shortcut in EditorShortcut.entries) {
            val chord = "${shortcut.shift}-${shortcut.key}-${shortcut.character}"
            assertNull("${shortcut.title} uses the same chord as ${seen[chord]}", seen[chord])
            seen[chord] = shortcut.title
        }
        assertEquals(EditorShortcut.entries.size, seen.size)
    }

    @Test fun theTableMatchesIos() {
        fun chord(s: EditorShortcut) = Triple(s.key, s.character, s.shift)
        assertEquals(Triple(Key.OTHER, 'z', false), chord(EditorShortcut.UNDO))
        assertEquals(Triple(Key.OTHER, 'z', true), chord(EditorShortcut.REDO))
        assertEquals(Triple(Key.OTHER, 'n', false), chord(EditorShortcut.NEW_SONG))
        assertEquals(Triple(Key.OTHER, 'o', false), chord(EditorShortcut.SONGS))
        assertEquals(Triple(Key.OTHER, 'd', false), chord(EditorShortcut.DUPLICATE_SONG))
        assertEquals(Triple(Key.OTHER, 'e', false), chord(EditorShortcut.EXPORT_WAV))
        assertEquals(Triple(Key.OTHER, 's', true), chord(EditorShortcut.SHARE_SONG))
        assertEquals(Triple(Key.OTHER, 'n', true), chord(EditorShortcut.NEW_PATTERN))
        assertEquals(Triple(Key.OTHER, 'a', true), chord(EditorShortcut.ARRANGEMENT))
        assertEquals(Triple(Key.BACKSPACE, null, false), chord(EditorShortcut.CLEAR_PATTERN))
        assertEquals(10, EditorShortcut.entries.size)
    }

    @Test fun titlesReadAsActions() {
        assertEquals(
            listOf(
                "Undo", "Redo", "New Song", "Songs", "Duplicate Song", "Export WAV",
                "Share Song File", "New Pattern", "Arrangement", "Clear Pattern",
            ),
            EditorShortcut.entries.map { it.title },
        )
    }

    @Test fun ctrlAndMetaBothMatch() {
        assertEquals(EditorShortcut.UNDO, EditorShortcut.match(Key.OTHER, "z", ctrl))
        assertEquals(EditorShortcut.UNDO, EditorShortcut.match(Key.OTHER, "z", KeyModifiers(meta = true)))
        assertEquals(EditorShortcut.REDO, EditorShortcut.match(Key.OTHER, "z", ctrlShift))
        assertEquals(EditorShortcut.REDO, EditorShortcut.match(Key.OTHER, "Z", ctrlShift))
        assertEquals(EditorShortcut.NEW_PATTERN, EditorShortcut.match(Key.OTHER, "n", ctrlShift))
        assertEquals(EditorShortcut.NEW_SONG, EditorShortcut.match(Key.OTHER, "n", ctrl))
        assertEquals(EditorShortcut.SHARE_SONG, EditorShortcut.match(Key.OTHER, "s", ctrlShift))
        assertEquals(EditorShortcut.ARRANGEMENT, EditorShortcut.match(Key.OTHER, "a", ctrlShift))
        assertEquals(EditorShortcut.CLEAR_PATTERN, EditorShortcut.match(Key.BACKSPACE, "", ctrl))
    }

    @Test fun bareShiftedOrAltPressesAreNotChords() {
        assertNull(EditorShortcut.match(Key.OTHER, "z", KeyModifiers()))
        assertNull(EditorShortcut.match(Key.OTHER, "z", KeyModifiers(shift = true)))
        assertNull(EditorShortcut.match(Key.OTHER, "z", KeyModifiers(ctrl = true, alt = true)))
        // Ctrl+S isn't a chord; only Ctrl+Shift+S shares.
        assertNull(EditorShortcut.match(Key.OTHER, "s", ctrl))
        assertNull(EditorShortcut.match(Key.OTHER, "a", ctrl))
        assertNull(EditorShortcut.match(Key.BACKSPACE, "", KeyModifiers()))
        assertNull(EditorShortcut.match(Key.BACKSPACE, "", ctrlShift))
        assertNull(EditorShortcut.match(Key.OTHER, "q", ctrl))
    }

    /** The grid sees every press first and must hand modified ones on. */
    @Test fun noChordIsClaimedByTheNoteRow() {
        for (shortcut in EditorShortcut.entries) {
            val characters = shortcut.character?.toString() ?: ""
            val modifiers = KeyModifiers(ctrl = true, shift = shortcut.shift)
            assertNull("${shortcut.title} would be typed", KeyAction.forKey(shortcut.key, characters, modifiers, 5))
            assertNull("${shortcut.title} would clear the cell", KeyAction.forKey(Key.BACKSPACE, characters, modifiers, 5))
        }
    }

    @Test fun noShortcutIsABareNoteRowLetter() {
        for (shortcut in EditorShortcut.entries) {
            val c = shortcut.character ?: continue
            // Every chord needs Ctrl (match refuses a bare press); the letters
            // themselves may be note keys, which is exactly why.
            assertNull(EditorShortcut.match(shortcut.key, c.toString(), KeyModifiers(shift = shortcut.shift)))
        }
    }

    @Test fun songChangingChordsWaitForSongBoundDialogs() {
        for (shortcut in EditorShortcut.entries) {
            assertFalse("$shortcut", shortcut.permitted(anyPresented = true, songBoundPresented = true))
            assertTrue("$shortcut", shortcut.permitted(anyPresented = false, songBoundPresented = false))
        }
    }

    @Test fun chordsThatOpenAScreenWaitForWhateverIsUp() {
        val opens = EditorShortcut.entries.filter { it.opensSurface }.toSet()
        assertEquals(
            setOf(EditorShortcut.SONGS, EditorShortcut.EXPORT_WAV, EditorShortcut.ARRANGEMENT, EditorShortcut.CLEAR_PATTERN),
            opens,
        )
        for (shortcut in EditorShortcut.entries) {
            // Songs, Arrangement and Export survive the song changing under
            // them, so Ctrl+N there stays a feature; a second screen doesn't.
            assertEquals("$shortcut", shortcut !in opens, shortcut.permitted(anyPresented = true, songBoundPresented = false))
        }
    }

    @Test fun groupsForTheSystemHelper() {
        assertEquals(
            listOf(EditorShortcut.UNDO, EditorShortcut.REDO),
            EditorShortcut.entries.filter { it.group == EditorShortcut.Group.EDIT },
        )
        assertEquals(
            listOf(
                EditorShortcut.NEW_SONG, EditorShortcut.SONGS, EditorShortcut.DUPLICATE_SONG,
                EditorShortcut.EXPORT_WAV, EditorShortcut.SHARE_SONG,
            ),
            EditorShortcut.entries.filter { it.group == EditorShortcut.Group.SONG },
        )
        assertEquals(
            listOf(EditorShortcut.NEW_PATTERN, EditorShortcut.ARRANGEMENT, EditorShortcut.CLEAR_PATTERN),
            EditorShortcut.entries.filter { it.group == EditorShortcut.Group.PATTERN },
        )
        assertEquals(listOf("Song", "Edit", "Pattern"), EditorShortcut.Group.entries.map { it.title })
    }

    @Test fun theUnmodifiedKeyListHasSevenRowsAndPointsAtCtrl() {
        val rows = UnmodifiedKeyHelp.ROWS
        assertEquals(7, rows.size)
        assertEquals(UnmodifiedKeyHelp.Row("Space", "Play or stop"), rows[0])
        assertEquals(UnmodifiedKeyHelp.Row("\u2190 \u2192 \u2191 \u2193", "Move the cursor"), rows[1])
        assertEquals(UnmodifiedKeyHelp.Row("A W S E D F T G Y H U J K", "Type a note, C upwards"), rows[2])
        assertEquals(UnmodifiedKeyHelp.Row("Z / X", "Octave down or up"), rows[3])
        assertEquals(UnmodifiedKeyHelp.Row("Return", "Type the selected note"), rows[4])
        assertEquals(UnmodifiedKeyHelp.Row("\\", "Arm or disarm a rest"), rows[5])
        assertEquals(UnmodifiedKeyHelp.Row("Delete", "Clear the step"), rows[6])
        assertEquals("KEYBOARD", UnmodifiedKeyHelp.HEADER)
        assertEquals("Hold Ctrl for the rest.", UnmodifiedKeyHelp.FOOTER)
    }
}
