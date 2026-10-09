package dev.individuation.chiptune.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.R
import dev.individuation.chiptune.core.model.ChannelKind

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

    /** Piano key caps: `Color(white: 0.88)` and `Color(white: 0.13)`. */
    val whiteKey = Color(0xFFE0E0E0)
    val blackKey = Color(0xFF212121)

    /** One accent per channel kind: tracks are coloured by the sound they make. */
    fun channel(kind: ChannelKind): Color = when (kind) {
        ChannelKind.PULSE1 -> pulse1
        ChannelKind.PULSE2 -> pulse2
        ChannelKind.TRIANGLE -> triangle
        ChannelKind.NOISE -> noise
    }

    /** Every 4th step is a beat, so it gets a brighter lane. */
    fun rowTint(step: Int): Color = if (step % 4 == 0) panelHigh else panel
}

object ChipRadii {
    val tray = 10.dp
    val inner = 7.dp
    val cell = 5.dp
    val panel = 8.dp
}

/**
 * JetBrains Mono (OFL 1.1, `assets/licenses/JetBrainsMono-OFL.txt`), the
 * stand-in for iOS's SF Mono. The NL cut: SF Mono has no ligatures, so `->`
 * and friends stay two characters here too.
 */
val JetBrainsMono = FontFamily(
    Font(R.font.jetbrains_mono_regular, FontWeight.Normal),
    Font(R.font.jetbrains_mono_medium, FontWeight.Medium),
    Font(R.font.jetbrains_mono_semibold, FontWeight.SemiBold),
    Font(R.font.jetbrains_mono_bold, FontWeight.Bold),
)

/** iOS's `chipFont(size, weight:)`: the monospaced tracker face, semibold by
 * default, scaling with the system font size (sp). Line height is trimmed to
 * the glyphs so fixed-height cells centre the text the way SwiftUI does. */
fun chipFont(size: Float, weight: FontWeight = FontWeight.SemiBold, letterSpacing: TextUnit = TextUnit.Unspecified): TextStyle =
    TextStyle(
        fontFamily = JetBrainsMono,
        fontWeight = weight,
        fontSize = size.sp,
        letterSpacing = letterSpacing,
        lineHeight = 1.2.em,
        lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.Both),
    )

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
    surfaceContainer = ChipColors.panelHigh,
    surfaceContainerHigh = ChipColors.panelHigh,
    surfaceContainerLow = ChipColors.panel,
    surfaceContainerHighest = ChipColors.grid,
    outline = ChipColors.grid,
    outlineVariant = ChipColors.grid,
    error = ChipColors.accentRed,
    onError = ChipColors.onLight,
)

/** Dark only, like the iOS app. Body text stays the system face (iOS uses
 * SF for sheets and alerts); the tracker chrome asks for [chipFont]. */
@Composable
fun ChiptuneTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = ChipScheme, typography = Typography(), content = content)
}
