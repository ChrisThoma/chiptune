package dev.individuation.chiptune.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** The app's palette; the hex values match the iOS theme. */
object ChipColors {
    val background = Color(0xFF0D0D17)
    val panel = Color(0xFF1A1A29)
    val panelHigh = Color(0xFF26263B)
    val grid = Color(0xFF33334D)
    val divider = grid.copy(alpha = 0.8f)
    val text = Color(0xFFE0E6F5)
    val dim = Color(0xFF80859E)
    val onLight = Color(0xFF0F0F1A)
    val onLightGreen = Color(0xFF0D7340)
    val accentGreen = Color(0xFF66F299)
    val accentRed = Color(0xFFFF6673)
    val pulse1 = Color(0xFFFF5973)
    val pulse2 = Color(0xFFFFC740)
    val triangle = Color(0xFF4DD9FF)
    val noise = Color(0xFFB38CFF)
}

object ChipRadii {
    val tray = 10.dp
    val inner = 7.dp
    val cell = 5.dp
    val panel = 8.dp
}

private val ChipScheme = darkColorScheme(
    primary = ChipColors.accentGreen,
    onPrimary = ChipColors.onLight,
    secondary = ChipColors.pulse2,
    onSecondary = ChipColors.onLight,
    tertiary = ChipColors.triangle,
    background = ChipColors.background,
    onBackground = ChipColors.text,
    surface = ChipColors.panel,
    onSurface = ChipColors.text,
    surfaceVariant = ChipColors.panelHigh,
    onSurfaceVariant = ChipColors.dim,
    outline = ChipColors.grid,
    outlineVariant = ChipColors.grid,
    error = ChipColors.accentRed,
    onError = ChipColors.onLight,
)

/** Dark only, like the iOS app. */
@Composable
fun ChiptuneTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = ChipScheme, content = content)
}
