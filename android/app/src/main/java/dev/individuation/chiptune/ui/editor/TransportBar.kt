package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.ui.layout.ChipLayout
import dev.individuation.chiptune.ui.layout.EditorChrome
import dev.individuation.chiptune.ui.layout.TempoInput
import dev.individuation.chiptune.ui.layout.TransportForm
import dev.individuation.chiptune.ui.layout.TransportPlayShape
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.ChipRadii
import dev.individuation.chiptune.ui.theme.chipFont

/** Play/stop, the PATT/SONG/ARR tray and tempo (port of `TransportBar`).
 * [chromeWidth] is the width the chrome column draws at. */
@Composable
fun TransportBar(editor: Editor, chromeWidth: Double) {
    val layout = LocalChipLayout.current
    val scale = metricScale()
    val form = EditorChrome.transportForm(layout, chromeWidth, scale)
    val trayHeight = (layout.trayHeight * scale).dpValue()
    val spacing = ChipLayout.CHROME_ROW_SPACING.dpValue()
    Box(Modifier.fillMaxWidth().padding(horizontal = ChipLayout.CHROME_ROW_PADDING.dpValue()).padding(bottom = 8.dp)) {
        when (form) {
            TransportForm.ROW -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(spacing)) {
                PlayButton(editor, trayHeight, fillsRow = false)
                ModeTray(editor, trayHeight, stretched = false)
                Spacer(Modifier.weight(1f).widthIn(min = ChipLayout.TRANSPORT_TRAY_GAP.dpValue()))
                TempoStepper(editor, trayHeight, stretched = false)
            }
            TransportForm.TWO_ROWS -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(spacing)) {
                    PlayButton(editor, trayHeight, fillsRow = false)
                    ModeTray(editor, trayHeight, stretched = false)
                }
                TempoStepper(editor, trayHeight, stretched = true)
            }
            TransportForm.STACKED -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PlayButton(editor, trayHeight, fillsRow = true)
                ModeTray(editor, trayHeight, stretched = true)
                TempoStepper(editor, trayHeight, stretched = true)
            }
        }
    }
}

/** The only saturated fill in the chrome and the biggest target. */
@Composable
private fun PlayButton(editor: Editor, height: Dp, fillsRow: Boolean) {
    val ui = editor.ui
    val playing by remember { derivedStateOf { ui.value.isPlaying } }
    val width = TransportPlayShape.width(fillsRow)
    val base = if (width != null) Modifier.width(width.dpValue()) else Modifier.fillMaxWidth()
    Box(
        base
            .height(height)
            .clip(RoundedCornerShape(ChipRadii.tray))
            .background(if (playing) ChipColors.accentRed else ChipColors.accentGreen)
            .plainClickable {
                editor.haptics.transport()
                editor.studio.togglePlay()
            }
            .semantics { contentDescription = if (playing) "Stop" else "Play" },
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(
            if (playing) Icons.Filled.Stop else Icons.Filled.PlayArrow,
            TransportPlayShape.glyphSize(metricScale().toDouble()).toFloat(),
            ChipColors.onLight,
        )
    }
}

/** PATT and SONG, a hairline, then ARR. [stretched] fills the stacked row. */
@Composable
private fun ModeTray(editor: Editor, height: Dp, stretched: Boolean) {
    val layout = LocalChipLayout.current
    val ui = editor.ui
    val songMode by remember { derivedStateOf { ui.value.songMode } }
    Row(
        (if (stretched) Modifier.fillMaxWidth() else Modifier).chipTray(height),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val segment = if (stretched) Modifier.weight(1f) else Modifier.width(layout.patternSegmentWidth.dpValue())
        Segment("PATT", "Pattern", on = !songMode, modifier = segment, height = height) { editor.studio.setSongMode(false) }
        Segment("SONG", "Song", on = songMode, modifier = segment, height = height) { editor.studio.setSongMode(true) }
        TrayDivider()
        Box(
            (if (stretched) Modifier.weight(1f) else Modifier.width(layout.arrButtonWidth.dpValue()))
                .height(height)
                .popoverAnchor(editor.presentation.anchors, PopoverAnchor.Arrangement)
                .plainClickable { editor.presentation.open(Presented.Arrangement) }
                .semantics { contentDescription = "Arrangement" },
            contentAlignment = Alignment.Center,
        ) {
            Text("ARR", style = chipFont(11f), color = ChipColors.text, maxLines = 1)
        }
    }
}

@Composable
private fun Segment(title: String, spoken: String, on: Boolean, modifier: Modifier, height: Dp, onClick: () -> Unit) {
    Box(
        modifier
            .height(height)
            .plainClickable(onClick = onClick)
            .semantics {
                contentDescription = spoken
                selected = on
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.fillMaxSize().padding(4.dp).clip(RoundedCornerShape(ChipRadii.inner))
                .background(if (on) ChipColors.text else ChipColors.panel),
        )
        Text(
            title,
            style = chipFont(11f, if (on) FontWeight.Bold else FontWeight.SemiBold),
            color = if (on) ChipColors.onLight else ChipColors.dim,
            maxLines = 1,
        )
    }
}

/** BPM, four at a time; the value opens the tempo dialog. */
@Composable
private fun TempoStepper(editor: Editor, height: Dp, stretched: Boolean) {
    val ui = editor.ui
    val tempo by remember { derivedStateOf { ui.value.song.tempo } }
    ChipStepper(
        label = "BPM",
        value = tempo.toInt(),
        range = Chip.TEMPO_MIN.toInt()..Chip.TEMPO_MAX.toInt(),
        onChange = { editor.studio.setTempo(editor.studio.song.tempo + it * 4) },
        onTapValue = { editor.presentation.open(Presented.Tempo) },
        modifier = (if (stretched) Modifier.fillMaxWidth() else Modifier).chipTray(height),
    )
}

/** "Tempo": type a BPM (iOS's alert with a number field). */
@Composable
fun TempoDialog(editor: Editor, onDismiss: () -> Unit) {
    val start = editor.studio.song.tempo.toInt().toString()
    var text by remember { mutableStateOf(TextFieldValue(start, TextRange(0, start.length))) }
    val focus = remember { FocusRequester() }
    fun set() {
        TempoInput.parse(text.text)?.let { editor.studio.setTempo(it) }
        onDismiss()
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ChipColors.panelHigh,
        title = { Text("Tempo") },
        text = {
            PresentedWindowKeys(onDismiss)
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("40 to 300 BPM", color = ChipColors.text)
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    placeholder = { Text("BPM") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { set() }),
                    // The field opens holding the tempo, so its placeholder
                    // never shows: name it for TalkBack.
                    modifier = Modifier.reportsTextEntryFocus().focusRequester(focus).semantics { contentDescription = "BPM" },
                )
            }
        },
        confirmButton = { TextButton(onClick = { set() }) { Text("Set") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
    LaunchedEffect(Unit) { focus.requestFocus() }
}
