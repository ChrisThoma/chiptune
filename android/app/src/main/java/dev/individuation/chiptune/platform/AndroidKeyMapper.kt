package dev.individuation.chiptune.platform

import android.content.res.Configuration
import android.view.KeyEvent
import dev.individuation.chiptune.core.studio.EditorShortcut
import dev.individuation.chiptune.core.studio.Key
import dev.individuation.chiptune.core.studio.KeyModifiers

/**
 * Android key events to the core's platform-free [Key] and [KeyModifiers].
 * Pure: it reads only the `KeyEvent` constants (inlined at compile time), so
 * it runs in JVM tests; the caller passes the event's fields in.
 */
object AndroidKeyMapper {
    /** One press, as `KeyAction.forKey` and `EditorShortcut.match` read it. */
    data class Press(val key: Key, val characters: String, val modifiers: KeyModifiers)

    /** Linux `KEY_BACKSLASH`: the physical key, whatever the layout calls it. */
    const val BACKSLASH_SCAN_CODE = 43

    /**
     * [unicodeChar] is `KeyEvent.getUnicodeChar(0)`: the key's character with
     * no modifiers, as iOS's `charactersIgnoringModifiers`. Null for a
     * modifier key on its own and for system keys the editor never reads.
     */
    fun press(keyCode: Int, scanCode: Int, metaState: Int, unicodeChar: Int): Press? {
        val key = key(keyCode, scanCode) ?: return null
        return Press(key, characters(keyCode, unicodeChar), modifiers(metaState))
    }

    fun key(keyCode: Int, scanCode: Int): Key? {
        // Matched on the physical key first, so a layout that types something
        // else there still arms a rest.
        if (keyCode == KeyEvent.KEYCODE_BACKSLASH || scanCode == BACKSLASH_SCAN_CODE) return Key.BACKSLASH
        return when (keyCode) {
            KeyEvent.KEYCODE_SPACE -> Key.SPACE
            KeyEvent.KEYCODE_DPAD_UP -> Key.UP
            KeyEvent.KEYCODE_DPAD_DOWN -> Key.DOWN
            KeyEvent.KEYCODE_DPAD_LEFT -> Key.LEFT
            KeyEvent.KEYCODE_DPAD_RIGHT -> Key.RIGHT
            KeyEvent.KEYCODE_DEL -> Key.BACKSPACE
            KeyEvent.KEYCODE_FORWARD_DEL -> Key.FORWARD_DELETE
            KeyEvent.KEYCODE_ENTER -> Key.ENTER
            KeyEvent.KEYCODE_NUMPAD_ENTER -> Key.NUMPAD_ENTER
            KeyEvent.KEYCODE_ESCAPE -> Key.ESCAPE
            KeyEvent.KEYCODE_PERIOD -> Key.PERIOD
            KeyEvent.KEYCODE_TAB -> Key.TAB
            in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z,
            in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9,
            KeyEvent.KEYCODE_COMMA, KeyEvent.KEYCODE_MINUS, KeyEvent.KEYCODE_EQUALS,
            KeyEvent.KEYCODE_LEFT_BRACKET, KeyEvent.KEYCODE_RIGHT_BRACKET,
            KeyEvent.KEYCODE_SEMICOLON, KeyEvent.KEYCODE_APOSTROPHE, KeyEvent.KEYCODE_SLASH,
            KeyEvent.KEYCODE_GRAVE, KeyEvent.KEYCODE_AT, KeyEvent.KEYCODE_POUND, KeyEvent.KEYCODE_PLUS,
            -> Key.OTHER
            else -> null
        }
    }

    /** The key map's character, or a letter's own when the map gave none. */
    fun characters(keyCode: Int, unicodeChar: Int): String {
        if (unicodeChar > 0 && !Character.isISOControl(unicodeChar)) return String(Character.toChars(unicodeChar))
        if (keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) return ('a' + (keyCode - KeyEvent.KEYCODE_A)).toString()
        if (keyCode == KeyEvent.KEYCODE_PERIOD) return "."
        return ""
    }

    fun modifiers(metaState: Int): KeyModifiers = KeyModifiers(
        ctrl = metaState and KeyEvent.META_CTRL_ON != 0,
        meta = metaState and KeyEvent.META_META_ON != 0,
        alt = metaState and KeyEvent.META_ALT_ON != 0,
        shift = metaState and KeyEvent.META_SHIFT_ON != 0,
    )

    /** The key code the system helper shows for [shortcut]. */
    fun keyCode(shortcut: EditorShortcut): Int {
        val c = shortcut.character
        if (c != null) return KeyEvent.KEYCODE_A + (c - 'a')
        return when (shortcut.key) {
            Key.BACKSPACE -> KeyEvent.KEYCODE_DEL
            else -> KeyEvent.KEYCODE_UNKNOWN
        }
    }

    fun metaState(shortcut: EditorShortcut): Int =
        KeyEvent.META_CTRL_ON or (if (shortcut.shift) KeyEvent.META_SHIFT_ON else 0)

    /** The "Keys" group of the system helper: the unmodified keys, one row
     * per key the helper can draw. */
    val UNMODIFIED_KEYS: List<Pair<String, Int>> = listOf(
        "Play or stop" to KeyEvent.KEYCODE_SPACE,
        "Cursor up" to KeyEvent.KEYCODE_DPAD_UP,
        "Cursor down" to KeyEvent.KEYCODE_DPAD_DOWN,
        "Cursor left" to KeyEvent.KEYCODE_DPAD_LEFT,
        "Cursor right" to KeyEvent.KEYCODE_DPAD_RIGHT,
        "Type a note, C upwards (A W S E D F T G Y H U J K)" to KeyEvent.KEYCODE_A,
        "Octave down" to KeyEvent.KEYCODE_Z,
        "Octave up" to KeyEvent.KEYCODE_X,
        "Type the selected note" to KeyEvent.KEYCODE_ENTER,
        "Arm or disarm a rest" to KeyEvent.KEYCODE_BACKSLASH,
        "Clear the step" to KeyEvent.KEYCODE_DEL,
        "Close what's open" to KeyEvent.KEYCODE_ESCAPE,
    )
}

/** Whether a hardware keyboard is attached and usable right now, from the
 * configuration (`LocalConfiguration` keeps it live). */
object KeyboardConnection {
    fun isConnected(keyboard: Int, hardKeyboardHidden: Int): Boolean =
        keyboard == Configuration.KEYBOARD_QWERTY && hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO
}
