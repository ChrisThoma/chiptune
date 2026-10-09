package dev.individuation.chiptune.ui

import android.graphics.Color as AndroidColor
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.individuation.chiptune.ui.theme.ChiptuneTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Dark window, so light icons: SystemBarStyle.dark keeps them light.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        setContent {
            ChiptuneTheme {
                val model: StudioViewModel = viewModel()
                val studio by model.studio.collectAsStateWithLifecycle()
                // iOS fades the splash out over 0.28 s, ease-out.
                Crossfade(targetState = studio, animationSpec = tween(280, easing = FastOutSlowInEasing), label = "splash") {
                    if (it == null) Splash() else DebugTransport(it)
                }
            }
        }
    }
}
