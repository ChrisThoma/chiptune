package dev.individuation.chiptune.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.ui.theme.ChipColors

/*
 * TEMPORARY (Phase 4): just enough UI to hear and check the audio host on a
 * device -- song name, Play/Stop, the playhead step and any audio error.
 * Phase 5's EditorScreen replaces this file; delete it then.
 */

@Composable
fun DebugTransport(studio: Studio) {
    val state by studio.state.collectAsStateWithLifecycle()
    Box(
        modifier = Modifier.fillMaxSize().background(ChipColors.background).safeDrawingPadding(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.padding(16.dp),
        ) {
            Text(state.song.name, color = ChipColors.text, fontFamily = FontFamily.Monospace, fontSize = 22.sp)
            Button(onClick = { studio.togglePlay() }) {
                Text(
                    if (state.isPlaying) "STOP" else "PLAY",
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                )
            }
            Text(
                "playing=${state.isPlaying} step=${state.playhead}",
                color = ChipColors.dim,
                fontFamily = FontFamily.Monospace,
            )
            state.audioError?.let {
                Text(it, color = ChipColors.accentRed, fontFamily = FontFamily.Monospace)
            }
        }
    }
}

@Composable
fun Splash() {
    Box(
        modifier = Modifier.fillMaxSize().background(ChipColors.background),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "CHIPTUNE",
            color = ChipColors.text,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
        )
    }
}
