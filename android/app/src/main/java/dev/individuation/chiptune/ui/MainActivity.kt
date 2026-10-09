package dev.individuation.chiptune.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color as AndroidColor
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.net.toUri
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.individuation.chiptune.ChiptuneApp
import dev.individuation.chiptune.platform.IncomingSongIntent
import dev.individuation.chiptune.BuildConfig
import dev.individuation.chiptune.ui.layout.ScreenshotMode
import dev.individuation.chiptune.ui.layout.SizeClass
import dev.individuation.chiptune.ui.theme.ChiptuneTheme

class MainActivity : ComponentActivity() {
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
        // A recreated activity still holds the intent that already imported.
        if (savedInstanceState == null) handleIncoming(intent)
        val screenshot = if (BuildConfig.DEBUG) screenshotMode(intent) else null
        setContent {
            ChiptuneTheme {
                val model: StudioViewModel = viewModel()
                AppRoot(model, screenshot)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncoming(intent)
    }

    /** A song file opened with or sent to Chiptune waits in the app until the Studio exists. */
    private fun handleIncoming(intent: Intent?) {
        intent ?: return
        @Suppress("DEPRECATION")
        val stream = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
        val parsed = IncomingSongIntent.parse(intent.action, intent.data?.toString(), stream?.toString(), intent.type)
        if (parsed is IncomingSongIntent.Result.Accepted) {
            (application as ChiptuneApp).incoming.offer(parsed.uri.toUri())
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
