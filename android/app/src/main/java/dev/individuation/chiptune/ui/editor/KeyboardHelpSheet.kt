package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.core.studio.UnmodifiedKeyHelp
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.chipFont

/** The hardware-key list as a phone sheet (iOS `KeyboardHelpView` adapted
 * to a sheet); at regular width it's a popover off the \u2022\u2022\u2022 menu. */
@Composable
fun KeyboardHelpSheet(onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss) {
        KeyboardHelpPanel(Modifier.navigationBarsPadding())
    }
}

/** The seven unmodified keys, then a pointer at Ctrl for the chords. */
@Composable
fun KeyboardHelpPanel(modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            UnmodifiedKeyHelp.HEADER,
            style = chipFont(11f, FontWeight.Bold, letterSpacing = 2.sp),
            color = ChipColors.dim,
            modifier = Modifier.semantics { heading() },
        )
        for (row in UnmodifiedKeyHelp.ROWS) {
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(row.keys, style = chipFont(13f, FontWeight.Bold), color = ChipColors.text)
                Text(row.action, style = chipFont(12f), color = ChipColors.dim)
            }
        }
        Text(UnmodifiedKeyHelp.FOOTER, style = chipFont(12f), color = ChipColors.dim)
    }
}
