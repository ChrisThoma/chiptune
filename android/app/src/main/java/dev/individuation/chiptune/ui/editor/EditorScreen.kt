package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.ui.arrangement.ArrangementSheet
import dev.individuation.chiptune.ui.export.ExportResultDialog
import dev.individuation.chiptune.ui.export.ExportResultHost
import dev.individuation.chiptune.ui.export.ExportSheet
import dev.individuation.chiptune.ui.instrument.InstrumentEditorSheet
import dev.individuation.chiptune.ui.layout.ChipLayout
import dev.individuation.chiptune.ui.layout.EditorChrome
import dev.individuation.chiptune.ui.layout.LayoutResolver
import dev.individuation.chiptune.ui.layout.ScreenshotMode
import dev.individuation.chiptune.ui.layout.SizeClass
import dev.individuation.chiptune.ui.layout.WindowSize
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

    Box(Modifier.fillMaxSize().background(ChipColors.background).songDropTarget(studio)) {
        BoxWithConstraints(
            Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout)),
        ) {
            val size = WindowSize(maxWidth.value.toDouble(), maxHeight.value.toDouble())
            // Phase 6 lays the keys beside the grid on wide tablets; until then
            // every window stacks, so nothing may believe the editor is docked.
            val layout = LayoutResolver.resolve(size, SizeClass.forWindowWidth(size.width)).withoutDockedInstrumentEditor
            val fontScale = LocalDensity.current.fontScale
            CompositionLocalProvider(LocalChipLayout provides layout) {
                if (EditorChrome.scrollsEditor(layout, fontScale)) {
                    ScrollingEditor(editor, layout, size)
                } else {
                    FixedEditor(editor, layout, size)
                }
            }
        }
        PresentedSurfaceHost(editor)
        ExportResultHost(editor)
        EditorErrorDialogs(editor)
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

/** Draws whatever [EditorPresentationState.current] says is up. */
@Composable
private fun PresentedSurfaceHost(editor: Editor) {
    val presentation = editor.presentation
    val layout = LocalChipLayout.current
    when (val current = presentation.current) {
        Presented.None -> Unit
        Presented.Songs -> SongListSheet(editor) { presentation.close(Presented.Songs) }
        Presented.Arrangement -> ArrangementSheet(editor, layout.isRegularWidth) { presentation.close(Presented.Arrangement) }
        Presented.Export -> ExportSheet(editor, layout.isRegularWidth) { presentation.close(Presented.Export) }
        is Presented.InstrumentEditor -> InstrumentEditorSheet(editor, current.track, current.showSound) { presentation.close(current) }
        is Presented.ExportResult -> ExportResultDialog(editor, current.file) { presentation.close(current) }
        Presented.KeyboardHelp -> KeyboardHelpSheet { presentation.close(Presented.KeyboardHelp) }
        is Presented.PatternRename -> PatternRenameSheet(editor, current.pattern) { presentation.close(current) }
        is Presented.ClearPattern -> ClearPatternDialog(editor, current.pattern) { presentation.close(current) }
        is Presented.DeletePattern -> DeletePatternDialog(editor, current.pattern) { presentation.close(current) }
        Presented.Tempo -> TempoDialog(editor) { presentation.close(Presented.Tempo) }
    }
}
