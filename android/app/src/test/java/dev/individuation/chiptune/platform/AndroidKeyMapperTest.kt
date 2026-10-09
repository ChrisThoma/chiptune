package dev.individuation.chiptune.platform

import android.content.res.Configuration
import android.view.KeyEvent
import dev.individuation.chiptune.core.studio.EditorShortcut
import dev.individuation.chiptune.core.studio.Key
import dev.individuation.chiptune.core.studio.KeyAction
import dev.individuation.chiptune.core.studio.KeyModifiers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** KeyEvent key codes, scan codes and meta state to the core's platform-free
 * [Key] and [KeyModifiers]. Only the constants are read (they're inlined), so
 * this runs on the plain JVM. */
class AndroidKeyMapperTest {
    private fun press(keyCode: Int, meta: Int = 0, unicode: Int = 0, scanCode: Int = 0) =
        AndroidKeyMapper.press(keyCode, scanCode, meta, unicode)

    @Test fun namedKeys() {
        assertEquals(Key.SPACE, press(KeyEvent.KEYCODE_SPACE)?.key)
        assertEquals(Key.UP, press(KeyEvent.KEYCODE_DPAD_UP)?.key)
        assertEquals(Key.DOWN, press(KeyEvent.KEYCODE_DPAD_DOWN)?.key)
        assertEquals(Key.LEFT, press(KeyEvent.KEYCODE_DPAD_LEFT)?.key)
        assertEquals(Key.RIGHT, press(KeyEvent.KEYCODE_DPAD_RIGHT)?.key)
        assertEquals(Key.BACKSPACE, press(KeyEvent.KEYCODE_DEL)?.key)
        assertEquals(Key.FORWARD_DELETE, press(KeyEvent.KEYCODE_FORWARD_DEL)?.key)
        assertEquals(Key.ENTER, press(KeyEvent.KEYCODE_ENTER)?.key)
        assertEquals(Key.ESCAPE, press(KeyEvent.KEYCODE_ESCAPE)?.key)
        assertEquals(Key.PERIOD, press(KeyEvent.KEYCODE_PERIOD)?.key)
        assertEquals(Key.TAB, press(KeyEvent.KEYCODE_TAB)?.key)
    }

    @Test fun keypadEnterIsItsOwnKeyAndStillTypes() {
        val p = press(KeyEvent.KEYCODE_NUMPAD_ENTER)!!
        assertEquals(Key.NUMPAD_ENTER, p.key)
        assertEquals(KeyAction.TypeSelected, KeyAction.forKey(p.key, p.characters, p.modifiers, 5))
    }

    @Test fun backslashByKeyCodeOrByScanCode() {
        assertEquals(Key.BACKSLASH, press(KeyEvent.KEYCODE_BACKSLASH)?.key)
        // A layout that reports the physical key under another code still
        // lands: Linux KEY_BACKSLASH is scan code 43.
        assertEquals(Key.BACKSLASH, press(KeyEvent.KEYCODE_POUND, scanCode = 43)?.key)
        assertEquals(Key.BACKSLASH, press(KeyEvent.KEYCODE_UNKNOWN, scanCode = 43)?.key)
        assertEquals(Key.OTHER, press(KeyEvent.KEYCODE_A, scanCode = 30, unicode = 'a'.code)?.key)
    }

    @Test fun lettersCarryTheirCharacter() {
        val a = press(KeyEvent.KEYCODE_A, unicode = 'a'.code)!!
        assertEquals(Key.OTHER, a.key)
        assertEquals("a", a.characters)
        assertEquals(KeyAction.Type(60), KeyAction.forKey(a.key, a.characters, a.modifiers, 5))
        // No character from the key map (Ctrl held, say): the letter's own.
        assertEquals("k", press(KeyEvent.KEYCODE_K)?.characters)
        assertEquals("z", press(KeyEvent.KEYCODE_Z, meta = KeyEvent.META_CTRL_ON)?.characters)
        assertEquals(".", press(KeyEvent.KEYCODE_PERIOD)?.characters)
    }

    @Test fun shiftIsAllowedThrough() {
        val p = press(KeyEvent.KEYCODE_W, meta = KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON, unicode = 'W'.code)!!
        assertEquals(KeyModifiers(shift = true), p.modifiers)
        assertEquals(KeyAction.Type(61), KeyAction.forKey(p.key, p.characters, p.modifiers, 5))
    }

    @Test fun ctrlAltAndMetaAreNotNotes() {
        for (meta in listOf(
            KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON,
            KeyEvent.META_ALT_ON or KeyEvent.META_ALT_LEFT_ON,
            KeyEvent.META_META_ON or KeyEvent.META_META_LEFT_ON,
        )) {
            val p = press(KeyEvent.KEYCODE_A, meta = meta, unicode = 'a'.code)!!
            assertNull("meta $meta", KeyAction.forKey(p.key, p.characters, p.modifiers, 5))
        }
        assertEquals(KeyModifiers(ctrl = true), AndroidKeyMapper.modifiers(KeyEvent.META_CTRL_ON))
        assertEquals(KeyModifiers(meta = true), AndroidKeyMapper.modifiers(KeyEvent.META_META_ON))
        assertEquals(KeyModifiers(alt = true), AndroidKeyMapper.modifiers(KeyEvent.META_ALT_ON))
        assertEquals(
            KeyModifiers(ctrl = true, shift = true),
            AndroidKeyMapper.modifiers(KeyEvent.META_CTRL_ON or KeyEvent.META_SHIFT_ON),
        )
    }

    @Test fun modifierKeysOnTheirOwnArentPresses() {
        for (code in listOf(
            KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT, KeyEvent.KEYCODE_CTRL_LEFT,
            KeyEvent.KEYCODE_CTRL_RIGHT, KeyEvent.KEYCODE_META_LEFT, KeyEvent.KEYCODE_META_RIGHT,
            KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_ALT_RIGHT, KeyEvent.KEYCODE_CAPS_LOCK,
            KeyEvent.KEYCODE_FUNCTION,
        )) {
            assertNull("$code", press(code))
        }
    }

    @Test fun systemKeysAreNeverClaimed() {
        // Back, volume and the like map to nothing the editor reads.
        for (code in listOf(KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_HOME)) {
            assertNull("$code", press(code))
        }
    }

    @Test fun everyShortcutHasAKeyCodeForTheSystemHelper() {
        assertEquals(KeyEvent.KEYCODE_Z, AndroidKeyMapper.keyCode(EditorShortcut.UNDO))
        assertEquals(KeyEvent.KEYCODE_Z, AndroidKeyMapper.keyCode(EditorShortcut.REDO))
        assertEquals(KeyEvent.KEYCODE_N, AndroidKeyMapper.keyCode(EditorShortcut.NEW_SONG))
        assertEquals(KeyEvent.KEYCODE_O, AndroidKeyMapper.keyCode(EditorShortcut.SONGS))
        assertEquals(KeyEvent.KEYCODE_D, AndroidKeyMapper.keyCode(EditorShortcut.DUPLICATE_SONG))
        assertEquals(KeyEvent.KEYCODE_E, AndroidKeyMapper.keyCode(EditorShortcut.EXPORT_WAV))
        assertEquals(KeyEvent.KEYCODE_S, AndroidKeyMapper.keyCode(EditorShortcut.SHARE_SONG))
        assertEquals(KeyEvent.KEYCODE_N, AndroidKeyMapper.keyCode(EditorShortcut.NEW_PATTERN))
        assertEquals(KeyEvent.KEYCODE_A, AndroidKeyMapper.keyCode(EditorShortcut.ARRANGEMENT))
        assertEquals(KeyEvent.KEYCODE_DEL, AndroidKeyMapper.keyCode(EditorShortcut.CLEAR_PATTERN))
        assertEquals(KeyEvent.META_CTRL_ON, AndroidKeyMapper.metaState(EditorShortcut.UNDO))
        assertEquals(KeyEvent.META_CTRL_ON or KeyEvent.META_SHIFT_ON, AndroidKeyMapper.metaState(EditorShortcut.REDO))
    }

    /** What the round trip through the mapper decides for each shortcut. */
    @Test fun everyShortcutMapsBackToItself() {
        for (shortcut in EditorShortcut.entries) {
            val code = AndroidKeyMapper.keyCode(shortcut)
            val unicode = shortcut.character?.code ?: 0
            val p = press(code, meta = AndroidKeyMapper.metaState(shortcut), unicode = unicode)!!
            assertEquals(shortcut, EditorShortcut.match(p.key, p.characters, p.modifiers))
        }
    }

    @Test fun theKeysGroupListsTheUnmodifiedKeys() {
        val rows = AndroidKeyMapper.UNMODIFIED_KEYS
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_SPACE })
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_BACKSLASH })
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_DEL })
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_ENTER })
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_DPAD_UP })
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_Z })
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_X })
        assertTrue(rows.any { it.second == KeyEvent.KEYCODE_ESCAPE })
    }

    @Test fun aHardwareKeyboardIsConnectedOnlyWhenQwertyAndExposed() {
        assertTrue(KeyboardConnection.isConnected(Configuration.KEYBOARD_QWERTY, Configuration.HARDKEYBOARDHIDDEN_NO))
        assertFalse(KeyboardConnection.isConnected(Configuration.KEYBOARD_QWERTY, Configuration.HARDKEYBOARDHIDDEN_YES))
        assertFalse(KeyboardConnection.isConnected(Configuration.KEYBOARD_NOKEYS, Configuration.HARDKEYBOARDHIDDEN_NO))
        assertFalse(KeyboardConnection.isConnected(Configuration.KEYBOARD_12KEY, Configuration.HARDKEYBOARDHIDDEN_NO))
        assertFalse(KeyboardConnection.isConnected(Configuration.KEYBOARD_UNDEFINED, Configuration.HARDKEYBOARDHIDDEN_UNDEFINED))
    }
}
