package dev.individuation.chiptune.ui.editor

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.key
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.ui.arrangement.ArrangementPanel
import dev.individuation.chiptune.ui.arrangement.ArrangementSheet
import dev.individuation.chiptune.ui.export.ExportResultDialog
import dev.individuation.chiptune.ui.export.ExportResultHost
import dev.individuation.chiptune.ui.export.ExportPanel
import dev.individuation.chiptune.ui.export.ExportSheet
import dev.individuation.chiptune.ui.instrument.InstrumentEditorBody
import dev.individuation.chiptune.ui.instrument.InstrumentEditorPanel
import dev.individuation.chiptune.ui.instrument.InstrumentEditorSheet
import dev.individuation.chiptune.ui.layout.ChipLayout
import dev.individuation.chiptune.ui.layout.EditorChrome
import dev.individuation.chiptune.ui.layout.LayoutResolver
import dev.individuation.chiptune.ui.layout.ScreenshotMode
import dev.individuation.chiptune.ui.layout.SizeClass
import dev.individuation.chiptune.ui.layout.SurfaceContainer
import dev.individuation.chiptune.ui.layout.SurfaceContainers
import dev.individuation.chiptune.ui.layout.SurfaceKind
import dev.individuation.chiptune.ui.layout.WindowSize
import dev.individuation.chiptune.ui.songs.SongListPanel
import dev.individuation.chiptune.ui.songs.SongListSheet
import dev.individuation.chiptune.ui.theme.ChipColors

/**
 * The editor (port of `ContentView`): title, transport and pattern rows, the
 * grid, and the keys under it.
 *
 * Insets: the window is drawn edge to edge. Everything sits inside the status
 * bar, navigation bar and cutout insets, and the layout is measured there --
 * but never through the IME (no `imePadding` above the `BoxWithConstraints`),
 * so raising the keyboard to type a name can't rebuild the editor under the
 * field ([ChipLayout.MEASUREMENT_IGNORES_IME]).
 */
@Composable
fun EditorScreen(
    studio: Studio,
    effects: EditorEffects? = null,
    screenshotMode: ScreenshotMode? = null,
    onScreenshotModeApplied: () -> Unit = {},
) {
    val ui = studio.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val presentation = rememberEditorPresentation(studio, ui)
    val haptics = rememberHaptics()
    val editorEffects = effects ?: remember(context) { AndroidEditorEffects(context) }
    val rename = remember { TitleRename() }
    val editor = remember(studio, presentation, editorEffects, haptics) {
        Editor(studio, ui, presentation, editorEffects, haptics, rename)
    }
    val keys = remember(editor) { EditorKeyHandler(editor) }
    HardwareKeysHook(keys)

    CompositionLocalProvider(LocalEditorKeyHandler provides keys) {
        Box(Modifier.fillMaxSize().background(ChipColors.background)) {
            BoxWithConstraints(
                Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout))
                    .onGloballyPositioned { presentation.anchors.window = it.boundsInWindow() },
            ) {
                val size = WindowSize(maxWidth.value.toDouble(), maxHeight.value.toDouble())
                val fontScale = LocalDensity.current.fontScale
                val resolved = LayoutResolver.resolve(size, SizeClass.forWindowWidth(size.width))
                val scrolls = EditorChrome.scrollsEditor(resolved, fontScale)
                // The scrolling editor always stacks, so nothing under it may
                // believe the instrument editor is docked (iOS does the same).
                val layout = if (scrolls) resolved.withoutDockedInstrumentEditor else resolved
                CompositionLocalProvider(LocalChipLayout provides layout) {
                    when {
                        scrolls -> ScrollingEditor(editor, layout, size)
                        layout.usesSideKeyboard -> SideEditor(editor, layout, size)
                        else -> FixedEditor(editor, layout, size)
                    }
                    PresentedSurfaceHost(editor)
                }
            }
            ExportResultHost(editor)
            EditorErrorDialogs(editor)
        }
    }

    // A song file waiting to be shared (Share song file). Phase 7's share
    // sheet clears it when the sheet closes; the placeholder hands it off now.
    LaunchedEffect(editor) {
        snapshotFlow { ui.value.shareFile }.collect { file ->
            if (file != null) {
                editor.effects.shareFile(file, EditorEffects.SONG_MIME)
                studio.shareFile = null
            }
        }
    }

    // Debug screenshot launches open the screen the shoot asked for.
    LaunchedEffect(screenshotMode) {
        when (screenshotMode) {
            ScreenshotMode.ARRANGEMENT -> presentation.open(Presented.Arrangement)
            ScreenshotMode.LIBRARY -> presentation.open(Presented.Songs)
            ScreenshotMode.EXPORT -> presentation.open(Presented.Export)
            ScreenshotMode.PLAYING -> studio.play()
            ScreenshotMode.PATTERN -> studio.selectPattern(1)
            // Docked, the host closes it again: the settings are on screen.
            ScreenshotMode.INSTRUMENT -> presentation.open(Presented.InstrumentEditor(0, showSound = true))
            null -> return@LaunchedEffect
        }
        onScreenshotModeApplied()
    }
}

/** Song name, transport and patterns, capped at the layout's width and centred. */
@Composable
private fun Chrome(editor: Editor, layout: ChipLayout, windowWidth: Double) {
    val chromeWidth = minOf(windowWidth, layout.chromeMaxWidth)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            if (layout.chromeMaxWidth.isFinite()) Modifier.widthIn(max = layout.chromeMaxWidth.dpValue()).fillMaxWidth() else Modifier.fillMaxWidth(),
        ) {
            TitleBar(editor)
            // Buttons and steppers take no focus, so the name field would keep
            // the keyboard while you plainly work on something else.
            Box(Modifier.endsRenameOnTouch(editor.rename)) { TransportBar(editor, chromeWidth) }
            Box(Modifier.endsRenameOnTouch(editor.rename)) { PatternBar(editor) }
        }
    }
}

/** The grid used to run straight into the keys; this is the breathing room. */
@Composable
private fun KeysDivider() {
    Box(
        Modifier.fillMaxWidth().padding(top = 10.dp).padding(horizontal = 14.dp).height(1.dp)
            .background(ChipColors.grid.copy(alpha = 0.5f)),
    )
}

@Composable
private fun FixedEditor(editor: Editor, layout: ChipLayout, size: WindowSize) {
    Column(Modifier.fillMaxSize()) {
        Chrome(editor, layout, size.width)
        GridView(editor, Modifier.weight(1f).fillMaxWidth().endsRenameOnTouch(editor.rename))
        KeysDivider()
        KeyboardView(editor, Modifier.padding(top = 10.dp).endsRenameOnTouch(editor.rename))
    }
}

/**
 * Landscape tablet: chrome and grid on the left, the keys in a column of
 * their own on the right with the selected track's sound settings docked
 * under them (iOS `editor(_:)` with a horizontal axis, and `keyPanel`).
 */
@Composable
private fun SideEditor(editor: Editor, layout: ChipLayout, size: WindowSize) {
    Row(Modifier.fillMaxSize().padding(bottom = 8.dp)) {
        Column(Modifier.weight(1f).fillMaxHeight()) {
            Chrome(editor, layout, size.width - layout.sideColumnWidth - 1)
            GridView(editor, Modifier.weight(1f).fillMaxWidth().endsRenameOnTouch(editor.rename))
        }
        Box(
            Modifier.padding(vertical = 12.dp).width(1.dp).fillMaxHeight()
                .background(ChipColors.grid.copy(alpha = 0.5f)),
        )
        Column(Modifier.width(layout.sideColumnWidth.dpValue()).fillMaxHeight()) {
            KeyboardView(editor, Modifier.endsRenameOnTouch(editor.rename))
            Box(
                Modifier.fillMaxWidth().padding(horizontal = 14.dp).padding(bottom = 10.dp).height(1.dp)
                    .background(ChipColors.grid.copy(alpha = 0.5f)),
            )
            DockedInstrumentEditor(editor, Modifier.weight(1f).fillMaxWidth())
        }
    }
}

/** The selected track's sound settings, always on screen in the side column. */
@Composable
private fun DockedInstrumentEditor(editor: Editor, modifier: Modifier) {
    val ui = editor.ui
    val track by remember { derivedStateOf { ui.value.selectedTrack } }
    val exists by remember { derivedStateOf { ui.value.selectedTrack in ui.value.song.tracks.indices } }
    Box(modifier) {
        // A docked panel waits for the selection to land somewhere real.
        if (exists) {
            key(track) { InstrumentEditorBody(editor, track, docked = true) }
        }
    }
}

/** Large text, or a window too short for the fixed editor: everything
 * scrolls, and the grid gets a floor of its own. */
@Composable
private fun ScrollingEditor(editor: Editor, layout: ChipLayout, size: WindowSize) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Chrome(editor, layout, size.width)
        GridView(
            editor,
            Modifier.fillMaxWidth().height(EditorChrome.scrollingGridHeight(size.height).dpValue()).endsRenameOnTouch(editor.rename),
        )
        KeysDivider()
        KeyboardView(editor, Modifier.padding(top = 10.dp).endsRenameOnTouch(editor.rename))
    }
}

/** Hands the activity's key events to [keys] while this editor is on screen. */
@Composable
private fun HardwareKeysHook(keys: EditorKeyHandler) {
    val host = LocalContext.current.findActivity() as? HardwareKeyHost ?: return
    DisposableEffect(host, keys) {
        val handler: (KeyEvent) -> Boolean = { keys.handle(it, presented = false) }
        host.hardwareKeyHandler = handler
        onDispose { if (host.hardwareKeyHandler === handler) host.hardwareKeyHandler = null }
    }
}

private fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
}

/** Draws whatever [EditorPresentationState.current] says is up, in the
 * container the window calls for ([SurfaceContainers]). */
@Composable
private fun PresentedSurfaceHost(editor: Editor) {
    val presentation = editor.presentation
    val layout = LocalChipLayout.current
    fun container(kind: SurfaceKind) = SurfaceContainers.container(kind, layout)
    when (val current = presentation.current) {
        Presented.None -> Unit
        Presented.Songs -> {
            val close = { presentation.close(Presented.Songs) }
            if (container(SurfaceKind.SONGS) == SurfaceContainer.DIALOG) {
                ChipCenteredDialog(close) { SongListPanel(editor, close) }
            } else {
                SongListSheet(editor, close)
            }
        }
        Presented.Arrangement -> {
            val close = { presentation.close(Presented.Arrangement) }
            if (container(SurfaceKind.ARRANGEMENT) == SurfaceContainer.POPOVER) {
                ChipPopover(editor, PopoverAnchor.Arrangement, SurfaceKind.ARRANGEMENT, close) { ArrangementPanel(editor, close) }
            } else {
                ArrangementSheet(editor, layout.isRegularWidth, close)
            }
        }
        Presented.Export -> {
            val close = { presentation.close(Presented.Export) }
            if (container(SurfaceKind.EXPORT) == SurfaceContainer.POPOVER) {
                ChipPopover(editor, PopoverAnchor.Menu, SurfaceKind.EXPORT, close) { ExportPanel(editor, close) }
            } else {
                ExportSheet(editor, layout.isRegularWidth, close)
            }
        }
        is Presented.InstrumentEditor -> {
            val close = { presentation.close(current) }
            when (container(SurfaceKind.INSTRUMENT_EDITOR)) {
                // A rotation into the side layout docks the sound settings;
                // leaving the popover up as well would show them twice.
                SurfaceContainer.DOCKED -> LaunchedEffect(current) { close() }
                SurfaceContainer.POPOVER, SurfaceContainer.DIALOG ->
                    ChipPopover(editor, PopoverAnchor.Track(current.track), SurfaceKind.INSTRUMENT_EDITOR, close) {
                        InstrumentEditorPanel(editor, current.track, close, current.showSound)
                    }
                SurfaceContainer.SHEET -> InstrumentEditorSheet(editor, current.track, current.showSound, close)
            }
        }
        is Presented.ExportResult -> ExportResultDialog(editor, current.file) { presentation.close(current) }
        Presented.KeyboardHelp -> {
            val close = { presentation.close(Presented.KeyboardHelp) }
            if (container(SurfaceKind.KEYBOARD_HELP) == SurfaceContainer.POPOVER) {
                ChipPopover(editor, PopoverAnchor.Menu, SurfaceKind.KEYBOARD_HELP, close) { KeyboardHelpPanel() }
            } else {
                KeyboardHelpSheet(close)
            }
        }
        is Presented.PatternRename -> PatternRenameSheet(editor, current.pattern) { presentation.close(current) }
        is Presented.ClearPattern -> ClearPatternDialog(editor, current.pattern) { presentation.close(current) }
        is Presented.DeletePattern -> DeletePatternDialog(editor, current.pattern) { presentation.close(current) }
        Presented.Tempo -> TempoDialog(editor) { presentation.close(Presented.Tempo) }
    }
}
