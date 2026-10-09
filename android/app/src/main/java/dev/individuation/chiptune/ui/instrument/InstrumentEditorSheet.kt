package dev.individuation.chiptune.ui.instrument

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.NameCap
import dev.individuation.chiptune.core.model.Track
import dev.individuation.chiptune.core.studio.ConfirmationCopy
import dev.individuation.chiptune.ui.editor.BarPill
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.ConfirmDialog
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.FormButtonRow
import dev.individuation.chiptune.ui.editor.FormCaption
import dev.individuation.chiptune.ui.editor.FormColors
import dev.individuation.chiptune.ui.editor.FormRow
import dev.individuation.chiptune.ui.editor.FormSection
import dev.individuation.chiptune.ui.editor.FormSeparator
import dev.individuation.chiptune.ui.editor.FormSlider
import dev.individuation.chiptune.ui.editor.FormSwitch
import dev.individuation.chiptune.ui.editor.SegmentedPicker
import dev.individuation.chiptune.ui.editor.SheetBar
import dev.individuation.chiptune.ui.editor.plainClickable
import dev.individuation.chiptune.ui.layout.Format
import dev.individuation.chiptune.ui.layout.InstrumentEditorCopy
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.chipFont
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * One track's sound settings (iOS `InstrumentEditor`), opened by tapping an
 * already-selected track header. [track] is the track index snapshotted when
 * it opened (iOS's rule: confirm-time reads of the selection act on the
 * wrong track).
 *
 * The holder reports this as the song-bound TRACK_SOUND presenter while it's
 * up. The sheet is only chrome around [InstrumentEditorPanel], which a
 * regular-width popover can host as is, and [InstrumentEditorBody], which
 * Phase 6 docks in the tablet side column.
 */
@Composable
fun InstrumentEditorSheet(editor: Editor, track: Int, showSound: Boolean = false, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss, containerColor = FormColors.sheet) {
        InstrumentEditorPanel(editor, track, onDismiss, showSound)
    }
}

/** The presented form: a bar titled with the track and a Done in its
 * channel colour, over the controls. Closes itself if the track goes. */
@Composable
fun InstrumentEditorPanel(editor: Editor, track: Int, onDismiss: () -> Unit, showSound: Boolean = false) {
    val ui = editor.ui
    val exists by remember(track) { derivedStateOf { track in ui.value.song.tracks.indices } }
    if (!exists) {
        LaunchedEffect(Unit) { onDismiss() }
        return
    }
    val label by remember(track) { derivedStateOf { ui.value.song.fullLabel(track) } }
    val kind by remember(track) { derivedStateOf { ui.value.song.tracks.getOrNull(track)?.kind ?: ChannelKind.PULSE1 } }
    Column(Modifier.fillMaxWidth()) {
        SheetBar(
            title = label,
            trailing = { BarPill("Done", onDismiss, color = ChipColors.channel(kind), bold = true) },
        )
        InstrumentEditorBody(editor, track, docked = false, onDismiss = onDismiss, showSound = showSound)
    }
}

/**
 * The controls, shared by the sheet and the docked column. [docked] swaps the
 * bar for a slim heading ("Sound settings for X" to TalkBack); [onDismiss] is
 * what Duplicate and Delete call after acting (a docked panel has nothing to
 * dismiss).
 */
@Composable
fun InstrumentEditorBody(
    editor: Editor,
    track: Int,
    docked: Boolean,
    onDismiss: () -> Unit = {},
    showSound: Boolean = false,
) {
    val studio = editor.studio
    val ui = editor.ui
    val view = LocalView.current
    val current by remember(track) { derivedStateOf { ui.value.song.tracks.getOrNull(track) } }
    val trackValue = current ?: return
    val kind = trackValue.kind
    val instrument = trackValue.instrument
    val accent = ChipColors.channel(kind)
    val label by remember(track) { derivedStateOf { ui.value.song.fullLabel(track) } }
    val canAddTrack by remember { derivedStateOf { ui.value.song.canAddTrack } }
    val trackCount by remember { derivedStateOf { ui.value.song.tracks.size } }
    val patternName by remember { derivedStateOf { ui.value.pattern.name } }

    // Snapshotted when raised: in SONG mode the selected pattern moves under
    // the dialog, and a docked panel's track can change while it's up.
    var pendingClear by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var pendingDelete by remember { mutableStateOf<Int?>(null) }

    val scroll = rememberScrollState()
    // Where the pulse width (or, without one, the arpeggio) section starts.
    var soundTop by remember { mutableStateOf<Int?>(null) }
    if (showSound) {
        LaunchedEffect(soundTop) {
            soundTop?.let { scroll.scrollTo((it - SOUND_ANCHOR_PX).coerceAtLeast(0)) }
        }
    }
    Column(
        Modifier.fillMaxWidth().verticalScroll(scroll).padding(horizontal = 16.dp).navigationBarsPadding(),
    ) {
        if (docked) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(start = 4.dp, bottom = 6.dp)
                    .clearAndSetSemantics {
                        contentDescription = InstrumentEditorCopy.dockedHeading(label)
                        heading()
                    },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.Tune, contentDescription = null, tint = accent, modifier = Modifier.size(13.dp))
                Text(label.uppercase(), style = chipFont(11f, FontWeight.Bold), color = accent, maxLines = 1)
            }
        }

        PresetSection(kind, instrument) { studio.applyPreset(it, track) }

        NameSection(editor, track, kind)

        FormSection(header = "Channel") {
            Box(Modifier.padding(horizontal = 16.dp).padding(top = 12.dp)) {
                SegmentedPicker(
                    labels = ChannelKind.entries.map { it.fullName },
                    selected = kind.ordinal,
                    onSelect = { studio.setKind(ChannelKind.entries[it], track) },
                    label = "Channel",
                    value = kind.fullName,
                )
            }
            FormCaption(InstrumentEditorCopy.CHANNEL_CAPTION)
        }

        FormSection(header = "Level", footer = InstrumentEditorCopy.levelFooter(instrument.sustain)) {
            FormSlider(
                title = "Volume",
                value = instrument.volume,
                range = InstrumentEditorCopy.VOLUME_RANGE,
                display = Format::percent,
                accent = accent,
                onChange = { studio.setVolume(track, it) },
            )
            FormSeparator()
            FormSwitch("Hold", instrument.sustain, accent) { studio.setSustain(track, it) }
            FormSeparator()
            FormSlider(
                title = "Decay",
                value = instrument.decay,
                range = InstrumentEditorCopy.DECAY_RANGE,
                display = InstrumentEditorCopy::decay,
                accent = accent,
                onChange = { studio.setDecay(track, it) },
                enabled = !instrument.sustain,
            )
        }

        if (kind.hasDuty) {
            FormSection(header = "Pulse width", modifier = Modifier.onGloballyPositioned { if (soundTop == null) soundTop = it.positionInParent().y.toInt() }) {
                Box(Modifier.padding(16.dp)) {
                    SegmentedPicker(
                        labels = Instrument.DUTY_LABELS,
                        selected = instrument.duty,
                        onSelect = { studio.setDuty(track, it) },
                        label = "Pulse width",
                        value = InstrumentEditorCopy.pulseWidthValue(instrument.duty),
                    )
                }
            }
        }

        FormSection(
            header = "Arpeggio",
            modifier = Modifier.onGloballyPositioned {
                if (!kind.hasDuty && soundTop == null) soundTop = it.positionInParent().y.toInt()
            },
        ) {
            Box(Modifier.padding(horizontal = 16.dp).padding(top = 12.dp)) {
                SegmentedPicker(
                    labels = InstrumentEditorCopy.ARPS.map { it.label },
                    // An off-menu shape (from a file) selects no segment.
                    selected = InstrumentEditorCopy.ARPS.indexOfFirst { it.offsets == instrument.arpeggio },
                    onSelect = { studio.setArpeggio(track, InstrumentEditorCopy.ARPS[it].offsets) },
                    label = "Arpeggio",
                    value = InstrumentEditorCopy.arpeggioValue(instrument.arpeggio),
                )
            }
            FormCaption(InstrumentEditorCopy.ARPEGGIO_CAPTION)
        }

        FormSection(footer = if (canAddTrack) null else InstrumentEditorCopy.TRACK_LIMIT_FOOTER) {
            FormButtonRow("Duplicate track", icon = Icons.Filled.LibraryAdd, enabled = canAddTrack, onClick = {
                studio.duplicateTrack(track)
                onDismiss()
            })
            FormSeparator()
            // Notes live in patterns, so this only empties the one on screen.
            FormButtonRow(InstrumentEditorCopy.clearTrackButton(patternName), color = FormColors.destructive, onClick = {
                pendingClear = track to studio.selectedPattern
            })
            FormSeparator()
            FormButtonRow("Delete track", color = FormColors.destructive, enabled = trackCount > 1, onClick = {
                pendingDelete = track
            })
        }
        Spacer(Modifier.size(12.dp))
    }

    pendingClear?.let { (target, pattern) ->
        val name = studio.song.patterns.getOrNull(pattern)?.name ?: ""
        ConfirmDialog(
            title = InstrumentEditorCopy.clearTrackTitle(name),
            message = ConfirmationCopy.CLEAR_TRACK,
            confirmLabel = "Clear track",
            destructive = true,
            onConfirm = { studio.clearTrack(target, pattern) },
            onDismiss = { pendingClear = null },
        )
    }
    pendingDelete?.let { target ->
        ConfirmDialog(
            title = ConfirmationCopy.deleteTrackTitle(studio.song.fullLabel(target)),
            message = ConfirmationCopy.DELETE_TRACK,
            confirmLabel = "Delete track",
            destructive = true,
            onConfirm = {
                // Dismiss first and remove on the next frame, so nothing
                // draws this sheet against the deleted index.
                onDismiss()
                view.post { studio.removeTrack(target) }
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun PresetSection(kind: ChannelKind, instrument: Instrument, apply: (InstrumentPreset) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val name = InstrumentEditorCopy.presetName(instrument, kind)
    FormSection(header = "Preset") {
        Box {
            FormRow(
                Modifier
                    .plainClickable { open = true }
                    .clearAndSetSemantics {
                        contentDescription = "Sound preset"
                        stateDescription = name
                        role = Role.DropdownList
                        onClick { open = true; true }
                    },
            ) {
                Text("Sound", color = FormColors.tint, fontSize = 17.sp, modifier = Modifier.weight(1f))
                Text(name, color = ChipColors.dim, fontSize = 17.sp)
                Icon(Icons.Filled.UnfoldMore, contentDescription = null, tint = ChipColors.dim, modifier = Modifier.size(16.dp))
            }
            DropdownMenu(
                expanded = open,
                onDismissRequest = { open = false },
                containerColor = ChipColors.panelHigh,
                modifier = Modifier.width(240.dp),
            ) {
                InstrumentPreset.presetsFor(kind).forEach { preset ->
                    DropdownMenuItem(
                        text = { Text(preset.name, color = ChipColors.text, style = MaterialTheme.typography.bodyLarge) },
                        onClick = {
                            open = false
                            apply(preset)
                        },
                    )
                }
            }
        }
        FormSeparator()
        FormCaption(InstrumentEditorCopy.PRESET_CAPTION)
    }
}

/** The track's name, capped at 16 graphemes as typed. A local draft, so the
 * field shows the clip; the stored name writes through as it changes. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NameSection(editor: Editor, track: Int, kind: ChannelKind) {
    val studio = editor.studio
    val ui = editor.ui
    val stored by remember(track) { derivedStateOf { ui.value.song.tracks.getOrNull(track)?.name } }
    var draft by remember(track) { mutableStateOf(stored ?: "") }
    // Undo (or a rename elsewhere) changes the stored name under the field.
    LaunchedEffect(stored) {
        NameCap.draftUpdate(draft, stored)?.let { draft = it }
    }
    // The sheet pads itself for the keyboard but doesn't scroll the field
    // into what's left, so the field asks once the keyboard is up.
    val reveal = remember { BringIntoViewRequester() }
    val scope = rememberCoroutineScope()
    FormSection(
        header = "Name",
        footer = InstrumentEditorCopy.nameFooter(draft),
        modifier = Modifier.bringIntoViewRequester(reveal),
    ) {
        FormRow {
            BasicTextField(
                value = draft,
                onValueChange = { typed ->
                    val capped = NameCap.clip(typed, Track.MAX_NAME_LENGTH)
                    draft = capped
                    studio.setTrackName(capped, track)
                },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = ChipColors.text, fontSize = 17.sp),
                cursorBrush = SolidColor(ChipColors.text),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    autoCorrectEnabled = false,
                    imeAction = ImeAction.Done,
                ),
                modifier = Modifier
                    .weight(1f)
                    .onFocusChanged { state ->
                        if (state.isFocused) {
                            scope.launch {
                                delay(KEYBOARD_SETTLE_MS)
                                reveal.bringIntoView()
                            }
                        }
                    }
                    .semantics { contentDescription = "Track name" },
                decorationBox = { field ->
                    Box {
                        if (draft.isEmpty()) Text(kind.fullName, color = ChipColors.dim, fontSize = 17.sp)
                        field()
                    }
                },
            )
        }
    }
}

/** The shoot's scroll stops a little above the section. */
private const val SOUND_ANCHOR_PX = 24

/** Long enough for the keyboard to have raised the sheet. */
private const val KEYBOARD_SETTLE_MS = 350L
