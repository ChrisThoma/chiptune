package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.core.studio.HelpGuide
import dev.individuation.chiptune.ui.layout.TextScale
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.chipFont

/** "How it works" as a phone sheet (iOS `HelpGuideView`); at regular width it's
 * a centred dialog. Open all the way: the list is the point of it. */
@Composable
fun HelpGuideSheet(start: HelpGuide.SectionId?, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss, skipPartiallyExpanded = true, containerColor = FormColors.sheet) {
        HelpGuidePanel(start, onDismiss, Modifier.navigationBarsPadding())
    }
}

/** One line per control, grouped the way the screen is, opened at [start] so a
 * (?) on a sheet lands on the part for that sheet. */
@Composable
fun HelpGuidePanel(start: HelpGuide.SectionId?, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val first = HelpGuide.sections.indexOfFirst { it.id == start }.coerceAtLeast(0)
    val list = rememberLazyListState(initialFirstVisibleItemIndex = first)
    Column(modifier.fillMaxWidth()) {
        SheetBar(title = "How it works", trailing = { BarPill("Done", onDismiss) })
        LazyColumn(
            state = list,
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(26.dp),
        ) {
            items(HelpGuide.sections, key = { it.id.name }) { section -> GuideSection(section) }
        }
    }
}

@Composable
private fun GuideSection(section: HelpGuide.Section) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            section.title.uppercase(),
            style = chipFont(11f, FontWeight.Bold, letterSpacing = 2.sp),
            color = ChipColors.dim,
            modifier = Modifier.semantics { heading() },
        )
        for (entry in section.entries) GuideRow(entry)
    }
}

/** At the accessibility text sizes a chip column would leave the sentence a few
 * characters a line, so the chip goes above it instead. */
@Composable
private fun GuideRow(entry: HelpGuide.Entry) {
    val stacked = TextScale.isAccessibilitySize(LocalDensity.current.fontScale)
    val label = Modifier.clearAndSetSemantics { contentDescription = "${entry.term}. ${entry.text}" }
    val sentence: @Composable () -> Unit = {
        Text(entry.text, fontSize = 15.sp, lineHeight = 20.sp, color = ChipColors.text)
    }
    if (stacked) {
        Column(label, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            GuideTerm(entry, Modifier)
            sentence()
        }
    } else {
        Row(label, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            GuideTerm(entry, Modifier.width(TERM_WIDTH.dp))
            sentence()
        }
    }
}

@Composable
private fun GuideTerm(entry: HelpGuide.Entry, modifier: Modifier) {
    Box(
        modifier
            .heightIn(min = 28.dp)
            .background(ChipColors.panelHigh, RoundedCornerShape(6.dp))
            .padding(horizontal = 4.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        val icon = entry.icon
        if (icon != null) {
            GuideGlyph(icon)
        } else {
            Text(entry.term, style = chipFont(11f, FontWeight.Bold), color = ChipColors.text, textAlign = TextAlign.Center)
        }
    }
}

/** The same glyph the control itself wears. */
@Composable
private fun GuideGlyph(icon: HelpGuide.Icon) {
    val vector = when (icon) {
        HelpGuide.Icon.PLAY -> Icons.Filled.PlayArrow
        HelpGuide.Icon.MUTE -> Icons.AutoMirrored.Filled.VolumeUp
        HelpGuide.Icon.SONGS -> Icons.AutoMirrored.Filled.QueueMusic
        HelpGuide.Icon.UNDO -> Icons.AutoMirrored.Filled.Undo
        HelpGuide.Icon.MENU -> return EllipsisCircle(15f)
    }
    Icon(vector, contentDescription = null, tint = ChipColors.text, modifier = Modifier.size(16.dp))
}

/** Wide enough for "Add section" on one line at the default text size. */
private const val TERM_WIDTH = 98

/** The small (?) on a sheet's bar. */
@Composable
fun HelpGuideButton(onClick: () -> Unit) {
    Box(
        Modifier
            .size(44.dp)
            .plainClickable(onClick = onClick)
            .semantics { contentDescription = "How it works" },
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.AutoMirrored.Outlined.HelpOutline, contentDescription = null, tint = ChipColors.dim, modifier = Modifier.size(20.dp))
    }
}
