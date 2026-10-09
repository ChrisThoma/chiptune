package dev.individuation.chiptune.platform

import android.view.KeyboardShortcutGroup
import android.view.KeyboardShortcutInfo
import dev.individuation.chiptune.core.studio.EditorShortcut

/** What the system's Meta+/ helper lists for the editor: the Ctrl chords by
 * [EditorShortcut.Group], then the unmodified keys. */
object KeyboardShortcutGroups {
    fun groups(): List<KeyboardShortcutGroup> {
        val chords = EditorShortcut.Group.entries.map { group ->
            KeyboardShortcutGroup(
                group.title,
                EditorShortcut.entries.filter { it.group == group }.map { shortcut ->
                    KeyboardShortcutInfo(shortcut.title, AndroidKeyMapper.keyCode(shortcut), AndroidKeyMapper.metaState(shortcut))
                },
            )
        }
        val keys = KeyboardShortcutGroup(
            "Keys",
            AndroidKeyMapper.UNMODIFIED_KEYS.map { (label, code) -> KeyboardShortcutInfo(label, code, 0) },
        )
        return chords + keys
    }
}
