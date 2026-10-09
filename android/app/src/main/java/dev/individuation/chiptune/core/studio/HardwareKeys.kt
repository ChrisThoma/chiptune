package dev.individuation.chiptune.core.studio

/**
 * Which note a letter key writes (port of `NoteKeys` in `HardwareKeys.swift`).
 * The home row plus the row above it, laid out as a piano: A is C, W is C
 * sharp, S is D, up to K, the octave above.
 */
object NoteKeys {
    /** Semitones above the octave's C. */
    val SEMITONES: Map<Char, Int> = mapOf(
        'a' to 0, 'w' to 1, 's' to 2, 'e' to 3, 'd' to 4, 'f' to 5, 't' to 6,
        'g' to 7, 'y' to 8, 'h' to 9, 'u' to 10, 'j' to 11, 'k' to 12,
    )

    const val OCTAVE_DOWN = 'z'
    const val OCTAVE_UP = 'x'

    /** The MIDI note a key writes at [octave] (C4 = 60 at octave 5), or null.
     * Past MIDI 127 the key is dropped rather than clamped. */
    fun note(character: Char, octave: Int): Int? {
        val semitone = SEMITONES[character.lowercaseChar()] ?: return null
        val midi = octave * 12 + semitone
        return if (midi in 0..127) midi else null
    }
}

/** A platform-neutral key, mapped from Android's `KeyEvent` keycodes by the
 * platform layer (Phase 6). Letters arrive as [OTHER] plus their characters. */
enum class Key {
    SPACE, UP, DOWN, LEFT, RIGHT, BACKSPACE, FORWARD_DELETE, ENTER, NUMPAD_ENTER,
    BACKSLASH, ESCAPE, PERIOD, TAB, OTHER,
}

/** [ctrl] and [meta] both stand in for iOS's Command. */
data class KeyModifiers(
    val ctrl: Boolean = false,
    val meta: Boolean = false,
    val alt: Boolean = false,
    val shift: Boolean = false,
)

/** What a key press means, worked out from the press alone so the whole
 * mapping is testable without a keyboard (port of `KeyAction`). */
sealed interface KeyAction {
    data object TogglePlay : KeyAction

    /** Arrow keys, in tracks and steps. */
    data class Move(val track: Int, val step: Int) : KeyAction

    data class Type(val note: Int) : KeyAction

    /** Return: writes whatever the on-screen keyboard holds -- the only way
     * to type a note off, since the letter row has none. */
    data object TypeSelected : KeyAction

    /** Arms or disarms a note off, like the REST button. */
    data object ToggleNoteOff : KeyAction

    data object Clear : KeyAction

    data class Octave(val delta: Int) : KeyAction

    /** Escape, or Ctrl+., while a sheet or popover is up. */
    data object Dismiss : KeyAction

    companion object {
        /** Null for anything the editor doesn't claim. Ctrl, Meta and Alt
         * belong to the system and to shortcuts; Shift is let through, since
         * it's how a capital arrives and the note row ignores case. */
        fun forKey(key: Key, characters: String, modifiers: KeyModifiers, octave: Int): KeyAction? {
            if (modifiers.ctrl || modifiers.meta || modifiers.alt) return null
            when (key) {
                Key.SPACE -> return TogglePlay
                Key.UP -> return Move(0, -1)
                Key.DOWN -> return Move(0, 1)
                Key.LEFT -> return Move(-1, 0)
                Key.RIGHT -> return Move(1, 0)
                Key.BACKSPACE, Key.FORWARD_DELETE -> return Clear
                Key.ENTER, Key.NUMPAD_ENTER -> return TypeSelected
                // Matched on the key rather than the character, so a layout
                // that puts backslash elsewhere still works.
                Key.BACKSLASH -> return ToggleNoteOff
                else -> Unit
            }
            val character = characters.firstOrNull() ?: return null
            return when (character.lowercaseChar()) {
                NoteKeys.OCTAVE_DOWN -> Octave(-1)
                NoteKeys.OCTAVE_UP -> Octave(1)
                else -> NoteKeys.note(character, octave)?.let { Type(it) }
            }
        }

        /** While a sheet or popover is up: close it, or nothing. Everything
         * else is passed on so shortcuts keep working. */
        fun forPresentedKey(key: Key, modifiers: KeyModifiers): KeyAction? = when {
            key == Key.ESCAPE -> Dismiss
            // A bare period is a period; only the Ctrl (or Meta) form cancels.
            key == Key.PERIOD && (modifiers.ctrl || modifiers.meta) -> Dismiss
            else -> null
        }
    }
}

/** Which held keys repeat. Android auto-repeats every held key; only the
 * arrows' repeats are honored -- a held letter filling a track with one note,
 * or a held Space starting and stopping playback, is never what was meant. */
object KeyRepeat {
    fun repeats(action: KeyAction): Boolean = action is KeyAction.Move
}

/** Runs a decoded key press: the only place a press changes anything. */
fun Studio.apply(action: KeyAction) {
    when (action) {
        KeyAction.TogglePlay -> togglePlay()
        is KeyAction.Move -> moveCursor(action.track, action.step)
        is KeyAction.Type -> typeNote(action.note)
        KeyAction.TypeSelected -> typeNote(selectedNote)
        KeyAction.ToggleNoteOff -> {
            hardwareKeyboardInUse = true
            toggleNoteOff()
        }
        KeyAction.Clear -> clearAtCursor()
        is KeyAction.Octave -> {
            hardwareKeyboardInUse = true
            shiftOctave(action.delta)
        }
        KeyAction.Dismiss -> requestDismiss()
    }
}
