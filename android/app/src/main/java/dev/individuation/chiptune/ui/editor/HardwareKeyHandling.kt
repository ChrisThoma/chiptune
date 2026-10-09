package dev.individuation.chiptune.ui.editor

import android.view.ActionMode
import android.view.KeyEvent
import android.view.KeyboardShortcutGroup
import android.view.Menu
import android.view.View
import android.view.Window
import androidx.compose.foundation.focusable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import dev.individuation.chiptune.core.studio.EditorShortcut
import dev.individuation.chiptune.core.studio.KeyAction
import dev.individuation.chiptune.core.studio.KeyRouting
import dev.individuation.chiptune.core.studio.apply
import dev.individuation.chiptune.platform.AndroidKeyMapper

/*
 * Hardware keys (port of the key catcher in `HardwareKeys.swift` and the
 * chords in `EditorCommands.swift`).
 *
 * Where keys are caught: `MainActivity.dispatchKeyEvent`, before the view
 * tree. Compose's `onPreviewKeyEvent` only sees keys while something under it
 * holds focus, and nothing in the grid or the keys is focusable, so a root
 * modifier would go deaf the moment focus left a text field -- the same
 * reason iOS uses a first responder rather than SwiftUI focus. A sheet,
 * dialog or popover is a window of its own, so keys go there instead; those
 * windows hook in with [PresentedWindowKeys] (dialogs and sheets) or
 * [presentedKeys] (popovers) and are read with the "something is presented"
 * rules: Escape and Ctrl+. dismiss, chords run behind their guards.
 *
 * A text field holding focus gets every key ([TextEntryFocus]): the fields
 * report themselves with [reportsTextEntryFocus]. Ending a rename clears
 * focus, which hands the keys straight back -- there is no first responder
 * to reclaim.
 */

/** Implemented by the activity that hosts the editor. */
interface HardwareKeyHost {
    var hardwareKeyHandler: ((KeyEvent) -> Boolean)?
}

/** Whether any text field has focus, in any window. */
object TextEntryFocus {
    private var holders by mutableStateOf(emptySet<Any>())

    val active: Boolean get() = holders.isNotEmpty()

    fun hold(token: Any) {
        if (token !in holders) holders = holders + token
    }

    fun release(token: Any) {
        if (token in holders) holders = holders - token
    }
}

/** A text field reports its focus, so the note row leaves its keys alone. */
@Composable
fun Modifier.reportsTextEntryFocus(): Modifier {
    val token = remember { Any() }
    DisposableEffect(token) { onDispose { TextEntryFocus.release(token) } }
    return onFocusChanged { if (it.isFocused) TextEntryFocus.hold(token) else TextEntryFocus.release(token) }
}

/**
 * Turns key events into editor actions: maps them ([AndroidKeyMapper]),
 * routes them ([KeyRouting]) and runs what comes out. One per editor.
 */
class EditorKeyHandler(private val editor: Editor) {
    /** Keys whose press was claimed, so their release is too (an unclaimed
     * Escape release would otherwise still be read as Back). */
    private val claimed = mutableSetOf<Int>()

    /** [presented] is true in a sheet's, dialog's or popover's window, or
     * when the editor has one up. [localDismiss] closes a window the
     * presentation holder doesn't own (a confirmation inside a sheet). */
    fun handle(event: KeyEvent, presented: Boolean, localDismiss: (() -> Unit)? = null): Boolean {
        if (event.action == KeyEvent.ACTION_UP) return claimed.remove(event.keyCode)
        if (event.action != KeyEvent.ACTION_DOWN) return false
        val press = AndroidKeyMapper.press(event.keyCode, event.scanCode, event.metaState, event.getUnicodeChar(0)) ?: return false
        val studio = editor.studio
        val outcome = KeyRouting.route(
            press.key,
            press.characters,
            press.modifiers,
            repeat = event.repeatCount > 0,
            textFocused = TextEntryFocus.active,
            presented = presented || editor.presentation.anyPresented,
            octave = studio.octave,
        )
        val handled = when (outcome) {
            KeyRouting.Outcome.Pass -> false
            KeyRouting.Outcome.Swallow -> true
            KeyRouting.Outcome.EndRename -> {
                editor.rename.endAnyTextEntry()
                true
            }
            is KeyRouting.Outcome.Act -> {
                studio.apply(outcome.action)
                if (outcome.action == KeyAction.Dismiss) localDismiss?.invoke()
                true
            }
            is KeyRouting.Outcome.Shortcut -> {
                run(outcome.shortcut)
                true
            }
        }
        if (handled) claimed.add(event.keyCode)
        return handled
    }

    /** Port of `EditorCommands.button`: guarded, and the rename ends first
     * so the chord lands on the state you can see. */
    fun run(shortcut: EditorShortcut) {
        val presentation = editor.presentation
        if (!shortcut.permitted(presentation.anyPresented, presentation.songBoundPresented)) return
        val studio = editor.studio
        editor.rename.end()
        when (shortcut) {
            EditorShortcut.UNDO -> studio.undo()
            EditorShortcut.REDO -> studio.redo()
            EditorShortcut.NEW_SONG -> studio.newSong()
            EditorShortcut.SONGS -> presentation.openSongs { editor.rename.end() }
            EditorShortcut.DUPLICATE_SONG -> studio.duplicateSong()
            EditorShortcut.EXPORT_WAV -> presentation.open(Presented.Export)
            EditorShortcut.SHARE_SONG -> studio.share(studio.song)
            EditorShortcut.NEW_PATTERN -> studio.addPattern()
            EditorShortcut.ARRANGEMENT -> presentation.open(Presented.Arrangement)
            EditorShortcut.CLEAR_PATTERN -> presentation.open(Presented.ClearPattern(studio.selectedPattern))
        }
    }
}

/** The editor's handler, for the windows it presents. Null outside an editor. */
val LocalEditorKeyHandler = staticCompositionLocalOf<EditorKeyHandler?> { null }

/**
 * Hooks this dialog's (or bottom sheet's) window into the editor's keys:
 * Escape and Ctrl+. dismiss it, chords run behind their guards. Call it
 * anywhere inside the dialog's content; [onDismiss] is what closes it.
 */
@Composable
fun PresentedWindowKeys(onDismiss: () -> Unit) {
    val handler = LocalEditorKeyHandler.current ?: return
    val view = LocalView.current
    val dismiss by rememberUpdatedState(onDismiss)
    DisposableEffect(view, handler) {
        val window = view.dialogWindow()
        if (window == null) {
            onDispose {}
        } else {
            val base = window.callback
            val wrapped = KeyWindowCallback(base) { handler.handle(it, presented = true) { dismiss() } }
            window.callback = wrapped
            onDispose { if (window.callback === wrapped) window.callback = base }
        }
    }
}

/** For a popover's content: a popover is a window without a `Window`, so its
 * keys are read through Compose focus. Escape already closes it (Popup's own
 * Back handling); this adds Ctrl+. and the chords. */
@Composable
fun Modifier.presentedKeys(onDismiss: () -> Unit): Modifier {
    val handler = LocalEditorKeyHandler.current ?: return this
    val dismiss by rememberUpdatedState(onDismiss)
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    return onPreviewKeyEvent { handler.handle(it.nativeKeyEvent, presented = true) { dismiss() } }
        .focusRequester(focus)
        .focusable()
}

private fun View.dialogWindow(): Window? {
    var node: Any? = this
    while (node != null) {
        if (node is DialogWindowProvider) return node.window
        node = (node as? View)?.parent
    }
    return null
}

/** Window.Callback that offers key events to [onKey] first. */
private class KeyWindowCallback(
    private val base: Window.Callback,
    private val onKey: (KeyEvent) -> Boolean,
) : Window.Callback by base {
    override fun dispatchKeyEvent(event: KeyEvent): Boolean = onKey(event) || base.dispatchKeyEvent(event)

    override fun onWindowStartingActionMode(callback: ActionMode.Callback?, type: Int): ActionMode? =
        base.onWindowStartingActionMode(callback, type)

    override fun onProvideKeyboardShortcuts(data: MutableList<KeyboardShortcutGroup>?, menu: Menu?, deviceId: Int) =
        base.onProvideKeyboardShortcuts(data, menu, deviceId)

    override fun onPointerCaptureChanged(hasCapture: Boolean) = base.onPointerCaptureChanged(hasCapture)
}
