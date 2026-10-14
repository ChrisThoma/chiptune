package dev.individuation.chiptune.core.studio

/**
 * The app's Ctrl chords, in one list (port of `EditorShortcut` in
 * `EditorCommands.swift`). Ctrl and Meta both stand in for iOS's Command.
 *
 * Every chord needs Ctrl: the note row owns A to K unmodified, and Ctrl is
 * also what tells [KeyAction.forKey] to leave the press alone. The \u2022\u2022\u2022 menu
 * rows and the title-bar buttons carry no chords of their own; this table is
 * the only place one is written down, and `onProvideKeyboardShortcuts` lists
 * it for the system's Meta+/ helper.
 */
enum class EditorShortcut(
    /** [Key.OTHER] for the letters, which match on [character]. */
    val key: Key,
    val character: Char?,
    /** Shift is part of the chord, not optional. */
    val shift: Boolean,
    /** Named after the action rather than the screen it opens. */
    val title: String,
    val group: Group,
    /** Opens a screen, so it also waits for whatever is already up. */
    val opensSurface: Boolean = false,
) {
    UNDO(Key.OTHER, 'z', false, "Undo", Group.EDIT),
    REDO(Key.OTHER, 'z', true, "Redo", Group.EDIT),
    NEW_SONG(Key.OTHER, 'n', false, "New Song", Group.SONG),
    SONGS(Key.OTHER, 'o', false, "Songs", Group.SONG, opensSurface = true),
    DUPLICATE_SONG(Key.OTHER, 'd', false, "Duplicate Song", Group.SONG),
    EXPORT(Key.OTHER, 'e', false, "Export\u2026", Group.SONG, opensSurface = true),
    SHARE_SONG(Key.OTHER, 's', true, "Share Song File", Group.SONG),
    NEW_PATTERN(Key.OTHER, 'n', true, "New Pattern", Group.PATTERN),
    ARRANGEMENT(Key.OTHER, 'a', true, "Arrangement", Group.PATTERN, opensSurface = true),
    CLEAR_PATTERN(Key.BACKSPACE, null, false, "Clear Pattern", Group.PATTERN, opensSurface = true),
    ;

    /** The system helper's sections, in the order they're listed. */
    enum class Group(val title: String) { SONG("Song"), EDIT("Edit"), PATTERN("Pattern") }

    /**
     * Whether the chord may run now. Every one waits while a dialog holds
     * state read from the song ([EditorPresentation.canChangeSong]); the ones
     * that open a screen also wait for anything already up, since a second
     * presentation would be lost ([EditorPresentation.canOpen]). Songs,
     * Arrangement and Export survive the song changing under them, so Ctrl+N
     * behind them still works.
     */
    fun permitted(anyPresented: Boolean, songBoundPresented: Boolean): Boolean =
        EditorPresentation.canChangeSong(songBoundPresented) &&
            (!opensSurface || EditorPresentation.canOpen(anyPresented))

    companion object {
        /** The chord a press makes, or null. Needs Ctrl or Meta and no Alt;
         * Shift must match exactly. */
        fun match(key: Key, characters: String, modifiers: KeyModifiers): EditorShortcut? {
            if (!(modifiers.ctrl || modifiers.meta) || modifiers.alt) return null
            val character = characters.firstOrNull()?.lowercaseChar()
            return entries.firstOrNull { shortcut ->
                shortcut.shift == modifiers.shift && shortcut.key == key &&
                    (shortcut.character == null || shortcut.character == character)
            }
        }
    }
}

/**
 * The keys that work without a modifier, listed for the \u2022\u2022\u2022 menu (port of
 * `UnmodifiedKeyHelp`). The system's Meta+/ helper only shows chords well,
 * so the half of the keyboard that matters most while writing a part is
 * written out here.
 */
object UnmodifiedKeyHelp {
    data class Row(val keys: String, val action: String)

    const val HEADER = "KEYBOARD"
    const val FOOTER = "Hold Ctrl for the rest."

    val ROWS: List<Row> = listOf(
        Row("Space", "Play or stop"),
        Row("\u2190 \u2192 \u2191 \u2193", "Move the cursor"),
        Row("A W S E D F T G Y H U J K", "Type a note, C upwards"),
        Row("Z / X", "Octave down or up"),
        Row("Return", "Type the selected note"),
        Row("\\", "Arm or disarm a rest"),
        Row("Delete", "Clear the step"),
    )
}

/**
 * Where a hardware key press goes (the Android side of iOS's `KeyCatcher`
 * first-responder rules plus the `EditorCommands` routing), decided from the
 * press and three facts about the screen.
 */
object KeyRouting {
    sealed interface Outcome {
        /** Not the editor's: the system (a text field, focus, Back) has it. */
        data object Pass : Outcome

        /** The editor's, but it does nothing: a held letter's repeat, or a
         * bare Escape that would otherwise fall back to Back and leave the app. */
        data object Swallow : Outcome

        data class Act(val action: KeyAction) : Outcome

        /** Run through [EditorShortcut.permitted] before acting. */
        data class Shortcut(val shortcut: EditorShortcut) : Outcome

        /** Escape in the song title: commit the name and hand the keys back. */
        data object EndRename : Outcome
    }

    /**
     * [repeat] is an auto-repeat of a held key; [textFocused] is any text
     * field holding focus; [presented] is a sheet, dialog or popover up.
     */
    fun route(
        key: Key,
        characters: String,
        modifiers: KeyModifiers,
        repeat: Boolean,
        textFocused: Boolean,
        presented: Boolean,
        octave: Int,
    ): Outcome {
        if (textFocused) {
            // The chords are app-wide, as iOS's commands are: one pressed
            // mid-rename ends the rename and runs (Ctrl+Z is the app's undo
            // here too, iOS's accepted side effect). Ctrl+Backspace stays the
            // field's word delete. Every other key is the field's.
            EditorShortcut.match(key, characters, modifiers)
                ?.takeIf { it != EditorShortcut.CLEAR_PATTERN }
                ?.let { return if (repeat) Outcome.Swallow else Outcome.Shortcut(it) }
            // Escape in the title (nothing presented) ends the rename; in a
            // dialog's field it closes the dialog the system way.
            if (key == Key.ESCAPE && !presented && !modifiers.anyCommand) {
                return if (repeat) Outcome.Swallow else Outcome.EndRename
            }
            return Outcome.Pass
        }
        if (presented) {
            KeyAction.forPresentedKey(key, modifiers)?.let { return if (repeat) Outcome.Swallow else Outcome.Act(it) }
            EditorShortcut.match(key, characters, modifiers)?.let { return if (repeat) Outcome.Swallow else Outcome.Shortcut(it) }
            return Outcome.Pass
        }
        EditorShortcut.match(key, characters, modifiers)?.let { return if (repeat) Outcome.Swallow else Outcome.Shortcut(it) }
        if (key == Key.ESCAPE) return Outcome.Swallow
        val action = KeyAction.forKey(key, characters, modifiers, octave) ?: return Outcome.Pass
        if (repeat && !KeyRepeat.repeats(action)) return Outcome.Swallow
        return Outcome.Act(action)
    }

    private val KeyModifiers.anyCommand: Boolean get() = ctrl || meta || alt
}
