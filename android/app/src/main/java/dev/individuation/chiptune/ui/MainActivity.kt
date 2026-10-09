package dev.individuation.chiptune.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color as AndroidColor
import android.os.Bundle
import android.view.KeyEvent
import android.view.KeyboardShortcutGroup
import android.view.Menu
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.individuation.chiptune.BuildConfig
import dev.individuation.chiptune.platform.KeyboardShortcutGroups
import dev.individuation.chiptune.ui.editor.HardwareKeyHost
import dev.individuation.chiptune.ui.layout.ScreenshotMode
import dev.individuation.chiptune.ui.layout.SizeClass
import dev.individuation.chiptune.ui.theme.ChiptuneTheme

class MainActivity : ComponentActivity(), HardwareKeyHost {
    /** Set by the editor while it's on screen (see `HardwareKeyHandling.kt`). */
    override var hardwareKeyHandler: ((KeyEvent) -> Boolean)? = null

    /** Ahead of the view tree, so keys reach the editor whatever has focus;
     * the handler passes on what a focused text field should get. (The
     * RestrictedApi flag is androidx.core marking its own override; this is
     * the platform `Activity.dispatchKeyEvent`.) */
    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        hardwareKeyHandler?.invoke(event) == true || super.dispatchKeyEvent(event)

    /** The Ctrl chords and the unmodified keys, for the Meta+/ helper. */
    override fun onProvideKeyboardShortcuts(data: MutableList<KeyboardShortcutGroup>?, menu: Menu?, deviceId: Int) {
        super.onProvideKeyboardShortcuts(data, menu, deviceId)
        data?.addAll(KeyboardShortcutGroups.groups())
    }

    @SuppressLint("SourceLockedOrientationActivity")
    override fun onCreate(savedInstanceState: Bundle?) {
        // Phones are portrait, as on iOS; tablets rotate (API 36 ignores the
        // lock at 600 dp and wider anyway). Before super, so the first frame
        // is already upright. A recreated activity (a foldable opening)
        // checks again.
        if (resources.configuration.smallestScreenWidthDp < SizeClass.REGULAR_MIN_WIDTH_DP) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        // Dark window, so light icons: SystemBarStyle.dark keeps them light.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        val screenshot = if (BuildConfig.DEBUG) screenshotMode(intent) else null
        setContent {
            ChiptuneTheme {
                val model: StudioViewModel = viewModel()
                AppRoot(model, screenshot)
            }
        }
    }

    /** Debug launches for screenshots: `--ez shotPlaying true` or `--es shotPlaying YES`. */
    private fun screenshotMode(intent: Intent?): ScreenshotMode? {
        val extras = intent?.extras ?: return null
        val values = ScreenshotMode.entries.associate { mode ->
            @Suppress("DEPRECATION")
            mode.key to extras.get(mode.key)
        }
        return ScreenshotMode.requested(values)
    }
}
