package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.ui.layout.ChipLayout
import dev.individuation.chiptune.ui.layout.KeyboardGeometry
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.ChipRadii
import dev.individuation.chiptune.ui.theme.chipFont

/** The piano that picks the note taps write into the grid (port of
 * `KeyboardView`). One octave everywhere but a wide docked column. */
@Composable
fun KeyboardView(editor: Editor, modifier: Modifier = Modifier) {
    val layout = LocalChipLayout.current
    CappedTextScale {
        Column(
            modifier
                .padding(horizontal = ChipLayout.KEYBOARD_HORIZONTAL_PADDING.dpValue())
                .padding(bottom = 6.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            KeyboardControls(editor)
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Keys(
                    editor,
                    Modifier
                        .height(layout.keyboardHeight.dpValue())
                        .then(if (layout.keyboardMaxWidth.isFinite()) Modifier.widthIn(max = layout.keyboardMaxWidth.dpValue()) else Modifier)
                        .fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun KeyboardControls(editor: Editor) {
    val ui = editor.ui
    val studio = editor.studio
    val octave by remember { derivedStateOf { ui.value.octave } }
    val note by remember { derivedStateOf { ui.value.selectedNote } }
    val kind by remember { derivedStateOf { ui.value.selectedKind } }
    val armed by remember { derivedStateOf { ui.value.noteOffArmed } }
    val trackLabel by remember { derivedStateOf { ui.value.song.fullLabel(ui.value.selectedTrack) } }

    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        // Paired rather than bracketing a readout: every white key already
        // names its octave. TalkBack still gets the number as each button's value.
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            OctaveButton(Icons.Filled.ChevronLeft, "Octave down", octave, octave > Studio.OCTAVE_RANGE.first) { studio.shiftOctave(-1) }
            OctaveButton(Icons.Filled.ChevronRight, "Octave up", octave, octave < Studio.OCTAVE_RANGE.last) { studio.shiftOctave(1) }
        }
        // Which track a tap lands on; while REST is armed, what REST does.
        // Centred in the space between the octave pair and REST.
        Column(
            Modifier.weight(1f).semantics(mergeDescendants = true) {},
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            Text(NoteName.label(note), style = chipFont(15f, FontWeight.Bold), color = ChipColors.channel(kind), maxLines = 1)
            Text(
                if (armed) "silence from here" else trackLabel,
                style = chipFont(9f),
                color = ChipColors.dim,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        // Writes a note-off instead of a pitch; tapped again, the pitch comes back.
        PadButton(
            onClick = { studio.toggleNoteOff() },
            active = armed,
            modifier = Modifier.clearAndSetSemantics {
                contentDescription = "Rest"
                selected = armed
                role = Role.Button
                onClick(if (armed) "Disarms, back to the note you had" else "Writes a rest") { studio.toggleNoteOff(); true }
            },
        ) { fg ->
            Text("REST", style = chipFont(12f), color = fg, maxLines = 1)
        }
    }
}

@Composable
private fun OctaveButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    octave: Int,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    PadButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.clearAndSetSemantics {
            contentDescription = label
            stateDescription = "${octave - 1}"
            role = Role.Button
            if (enabled) onClick { onClick(); true } else disabled()
        },
    ) { fg -> SymbolIcon(icon, 18f, fg) }
}

/** White keys in a row, black keys over the gaps (see [KeyboardGeometry]). */
@Composable
private fun Keys(editor: Editor, modifier: Modifier) {
    val layout = LocalChipLayout.current
    val ui = editor.ui
    val octave by remember { derivedStateOf { ui.value.octave } }
    val selectedNote by remember { derivedStateOf { ui.value.selectedNote } }
    val kind by remember { derivedStateOf { ui.value.selectedKind } }
    val octaves = maxOf(1, layout.keyboardOctaves)
    val whiteOffsets = KeyboardGeometry.whiteOffsets(octaves)
    val blackKeys = KeyboardGeometry.blackKeys(octaves)
    val base = octave * 12
    val accent = ChipColors.channel(kind)

    BoxWithConstraints(modifier) {
        val geometry = KeyboardGeometry(maxWidth.value.toDouble(), whiteOffsets.size)
        Row(Modifier.fillMaxWidth().fillMaxHeight(), horizontalArrangement = Arrangement.spacedBy(ChipLayout.WHITE_KEY_SPACING.dpValue())) {
            for (offset in whiteOffsets) {
                val midi = base + offset
                PianoKey(editor, midi, black = false, selected = selectedNote == midi, accent = accent, labelSize = layout.keyLabelSize.toFloat(), modifier = Modifier.weight(1f).fillMaxHeight())
            }
        }
        for ((offset, after) in blackKeys) {
            val midi = base + offset
            PianoKey(
                editor,
                midi,
                black = true,
                selected = selectedNote == midi,
                accent = accent,
                labelSize = 0f,
                modifier = Modifier
                    .offset(x = geometry.blackKeyOffset(after).dpValue())
                    .width(geometry.blackWidth.dpValue())
                    .height(maxHeight * 0.6f),
            )
        }
    }
}

@Composable
private fun PianoKey(editor: Editor, midi: Int, black: Boolean, selected: Boolean, accent: Color, labelSize: Float, modifier: Modifier) {
    val note = midi.coerceIn(-128, 127)
    val shape = RoundedCornerShape(ChipRadii.cell)
    val label = NoteName.label(note)
    Box(
        modifier
            .clip(shape)
            .background(if (selected) accent else if (black) ChipColors.blackKey else ChipColors.whiteKey)
            .border(1.dp, Color.Black.copy(alpha = 0.35f), shape)
            .pointerInput(note) {
                detectTapGestures {
                    editor.studio.selectedNote = note
                    editor.studio.audition(note)
                }
            }
            .clearAndSetSemantics {
                contentDescription = "Note $label"
                this.selected = selected
                role = Role.Button
                onClick {
                    editor.studio.selectedNote = note
                    editor.studio.audition(note)
                    true
                }
            },
        contentAlignment = Alignment.BottomCenter,
    ) {
        if (!black) {
            Text(
                label,
                style = chipFont(labelSize),
                color = ChipColors.onLight.copy(alpha = if (selected) 0.7f else 0.62f),
                maxLines = 1,
                softWrap = false,
                modifier = Modifier.padding(bottom = 5.dp),
            )
        }
    }
}
