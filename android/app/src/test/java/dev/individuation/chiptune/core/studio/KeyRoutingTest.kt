package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.studio.KeyRouting.Outcome
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Where a hardware key press goes: the note row, a Ctrl chord, the dismiss
 * gesture, or back to the system. The Android side of iOS's `KeyCatcher`
 * (first-responder rules) and `EditorCommands` guards, as one pure function.
 */
class KeyRoutingTest {
    private val none = KeyModifiers()
    private val ctrl = KeyModifiers(ctrl = true)

    private fun route(
        key: Key,
        characters: String = "",
        modifiers: KeyModifiers = none,
        repeat: Boolean = false,
        textFocused: Boolean = false,
        presented: Boolean = false,
    ) = KeyRouting.route(key, characters, modifiers, repeat, textFocused, presented, octave = 5)

    @Test fun theNoteRowTypesWithNothingUp() {
        assertEquals(Outcome.Act(KeyAction.Type(60)), route(Key.OTHER, "a"))
        assertEquals(Outcome.Act(KeyAction.TogglePlay), route(Key.SPACE))
        assertEquals(Outcome.Act(KeyAction.Move(0, 1)), route(Key.DOWN))
        assertEquals(Outcome.Act(KeyAction.ToggleNoteOff), route(Key.BACKSLASH))
        assertEquals(Outcome.Act(KeyAction.Clear), route(Key.BACKSPACE))
    }

    @Test fun shiftStillTypes() {
        assertEquals(Outcome.Act(KeyAction.Type(60)), route(Key.OTHER, "A", KeyModifiers(shift = true)))
    }

    @Test fun ctrlAltAndMetaNeverReachTheNoteRow() {
        assertEquals(Outcome.Pass, route(Key.OTHER, "w", ctrl))
        assertEquals(Outcome.Pass, route(Key.OTHER, "a", KeyModifiers(alt = true)))
        assertEquals(Outcome.Pass, route(Key.OTHER, "k", KeyModifiers(meta = true)))
        assertEquals(Outcome.Pass, route(Key.SPACE, modifiers = ctrl))
    }

    @Test fun chordsAreShortcuts() {
        assertEquals(Outcome.Shortcut(EditorShortcut.UNDO), route(Key.OTHER, "z", ctrl))
        assertEquals(Outcome.Shortcut(EditorShortcut.SONGS), route(Key.OTHER, "o", KeyModifiers(meta = true)))
        assertEquals(Outcome.Shortcut(EditorShortcut.CLEAR_PATTERN), route(Key.BACKSPACE, modifiers = ctrl))
    }

    /** Android repeats every held key; only the arrows' repeats count. */
    @Test fun onlyArrowRepeatsAreHonored() {
        assertEquals(Outcome.Act(KeyAction.Move(0, 1)), route(Key.DOWN, repeat = true))
        assertEquals(Outcome.Act(KeyAction.Move(-1, 0)), route(Key.LEFT, repeat = true))
        assertEquals(Outcome.Swallow, route(Key.OTHER, "a", repeat = true))
        assertEquals(Outcome.Swallow, route(Key.SPACE, repeat = true))
        assertEquals(Outcome.Swallow, route(Key.BACKSPACE, repeat = true))
        assertEquals(Outcome.Swallow, route(Key.OTHER, "z", ctrl, repeat = true))
    }

    /** Escape with nothing up does nothing -- and mustn't fall back to Back
     * and leave the app. */
    @Test fun escapeWithNothingUpIsSwallowed() {
        assertEquals(Outcome.Swallow, route(Key.ESCAPE))
    }

    @Test fun aFocusedTextFieldGetsEveryUnchordedKey() {
        assertEquals(Outcome.Pass, route(Key.OTHER, "a", textFocused = true))
        assertEquals(Outcome.Pass, route(Key.SPACE, textFocused = true))
        assertEquals(Outcome.Pass, route(Key.LEFT, textFocused = true))
        assertEquals(Outcome.Pass, route(Key.BACKSPACE, textFocused = true))
        // Ctrl+A, Ctrl+C and the like aren't chords; the field keeps them.
        assertEquals(Outcome.Pass, route(Key.OTHER, "a", ctrl, textFocused = true))
        assertEquals(Outcome.Pass, route(Key.OTHER, "c", ctrl, textFocused = true))
    }

    /** The chords are app-wide, as on iOS: one pressed mid-rename ends the
     * rename and runs (Ctrl+Z is the app's undo there too). */
    @Test fun chordsStillRunFromATextField() {
        assertEquals(Outcome.Shortcut(EditorShortcut.UNDO), route(Key.OTHER, "z", ctrl, textFocused = true))
        assertEquals(Outcome.Shortcut(EditorShortcut.SONGS), route(Key.OTHER, "o", ctrl, textFocused = true))
        assertEquals(Outcome.Swallow, route(Key.OTHER, "z", ctrl, textFocused = true, repeat = true))
        // Ctrl+Backspace in a field deletes a word; it's the field's.
        assertEquals(Outcome.Pass, route(Key.BACKSPACE, modifiers = ctrl, textFocused = true))
    }

    @Test fun escapeInTheTitleEndsTheRename() {
        assertEquals(Outcome.EndRename, route(Key.ESCAPE, textFocused = true))
        assertEquals(Outcome.Swallow, route(Key.ESCAPE, textFocused = true, repeat = true))
        // In a dialog's field it closes the dialog the system way.
        assertEquals(Outcome.Pass, route(Key.ESCAPE, textFocused = true, presented = true))
    }

    @Test fun withSomethingUpOnlyTheDismissGestureAndChordsAct() {
        assertEquals(Outcome.Act(KeyAction.Dismiss), route(Key.ESCAPE, presented = true))
        assertEquals(Outcome.Act(KeyAction.Dismiss), route(Key.PERIOD, ".", ctrl, presented = true))
        assertEquals(Outcome.Act(KeyAction.Dismiss), route(Key.PERIOD, ".", KeyModifiers(meta = true), presented = true))
        assertEquals(Outcome.Pass, route(Key.PERIOD, ".", presented = true))
        assertEquals(Outcome.Pass, route(Key.OTHER, "a", presented = true))
        assertEquals(Outcome.Pass, route(Key.SPACE, presented = true))
        assertEquals(Outcome.Pass, route(Key.DOWN, presented = true))
        // Commands keep firing behind a sheet; their guards decide.
        assertEquals(Outcome.Shortcut(EditorShortcut.NEW_SONG), route(Key.OTHER, "n", ctrl, presented = true))
        assertEquals(Outcome.Swallow, route(Key.ESCAPE, presented = true, repeat = true))
    }

    @Test fun ctrlPeriodWithNothingUpIsLeftAlone() {
        assertEquals(Outcome.Pass, route(Key.PERIOD, ".", ctrl))
    }
}
