package dev.individuation.chiptune.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.ui.editor.EditorScreen
import dev.individuation.chiptune.ui.layout.ScreenshotMode
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.chipFont

/** SwiftUI's `.easeOut` and `.easeInOut`. */
private val EaseOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)
private val EaseInOut = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)

/**
 * The splash while the Studio builds, then the editor, crossfaded over
 * 0.28 s ease-out as on iOS. [screenshotMode] is applied once, after the
 * Studio is ready (debug builds only pass one).
 */
@Composable
fun AppRoot(model: StudioViewModel, screenshotMode: ScreenshotMode?) {
    val studio by model.studio.collectAsStateWithLifecycle()
    var screenshotApplied by rememberSaveable { mutableStateOf(false) }
    Crossfade(targetState = studio, animationSpec = tween(280, easing = EaseOut), label = "splash") { built ->
        if (built == null) {
            Splash()
        } else {
            EditorScreen(
                studio = built,
                screenshotMode = if (screenshotApplied) null else screenshotMode,
                onScreenshotModeApplied = { screenshotApplied = true },
            )
        }
    }
}

/** Four bars, one per starting channel, and the name. */
@Composable
fun Splash() {
    val heights = listOf(46f, 28f, 52f, 34f)
    val transition = rememberInfiniteTransition(label = "splash bars")
    Box(
        Modifier.fillMaxSize().background(ChipColors.background).clearAndSetSemantics { contentDescription = "Chiptune, loading" },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Row(
                Modifier.height(52.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                ChannelKind.entries.forEachIndexed { i, kind ->
                    val height by transition.animateFloat(
                        initialValue = 12f,
                        targetValue = heights[i],
                        animationSpec = infiniteRepeatable(
                            tween(420, easing = EaseInOut),
                            RepeatMode.Reverse,
                            StartOffset(i * 90),
                        ),
                        label = "bar $i",
                    )
                    Box(
                        Modifier.width(11.dp).height(height.dp)
                            .background(ChipColors.channel(kind), RoundedCornerShape(2.dp)),
                    )
                }
            }
            Text("CHIPTUNE", style = chipFont(20f, FontWeight.Bold, letterSpacing = 6.sp), color = ChipColors.text)
        }
    }
}
