package dev.individuation.chiptune

import android.app.Application
import android.os.Looper
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import dev.individuation.chiptune.core.audio.ChipCore
import dev.individuation.chiptune.core.audio.ExportRenderer
import dev.individuation.chiptune.core.store.FileSongStore
import dev.individuation.chiptune.core.studio.AppPhase
import dev.individuation.chiptune.core.studio.ReviewPromptTracker
import dev.individuation.chiptune.core.studio.ScenePhasePolicy
import dev.individuation.chiptune.core.studio.SongShareWriter
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.platform.AndroidAudioOutput
import dev.individuation.chiptune.platform.AndroidScheduler
import dev.individuation.chiptune.platform.AudioOutputEvents
import dev.individuation.chiptune.platform.AudioRate
import dev.individuation.chiptune.platform.IncomingImports
import dev.individuation.chiptune.platform.ScreenOnExportKeepAlive
import dev.individuation.chiptune.platform.ShareRoots
import dev.individuation.chiptune.platform.SharedPrefsKeyValueStore
import dev.individuation.chiptune.platform.video.Mp4Writer
import java.io.File
import java.util.concurrent.Executors

/**
 * The app graph. The [Studio] is a process singleton: it owns the audio
 * engine, and a second one would mean a second AudioTrack playing over the
 * first. Activities and ViewModels come and go; they reach it through
 * [studio] / [buildStudio].
 *
 * Who builds what, all on the main thread, inside [buildStudio]:
 * native rate -> [ChipCore] at that rate -> [AndroidAudioOutput] around it ->
 * prefs, [FileSongStore], [SongShareWriter], the export renderer (with the
 * MediaCodec [Mp4Writer] for videos) and its
 * single-thread executor, [AndroidScheduler] -> [Studio] (which reads the
 * library and the last song from disk) -> the output's events wired to the
 * Studio's hooks. The only other threads are the output's render thread and
 * the export executor.
 *
 * [onCreate] only registers the process lifecycle observer; building the
 * Studio is left to the activity, after the splash has painted (iOS waits
 * 40 ms for the same reason).
 */
class ChiptuneApp : Application() {

    /** The Studio, once [buildStudio] has run. Main thread only. */
    /** Song files that arrived by VIEW/SEND, waiting for the Studio. */
    val incoming = IncomingImports()

    /** Holds the screen on while a video renders; [AppRoot] watches it.
     * Built on first use, on the main thread, after [onCreate]. */
    val exportKeepAlive: ScreenOnExportKeepAlive by lazy { ScreenOnExportKeepAlive() }

    var studio: Studio? = null
        private set

    /** The review prompt's export counts, kept with the app's other prefs. */
    val reviewPrompt: ReviewPromptTracker by lazy { ReviewPromptTracker(SharedPrefsKeyValueStore(this)) }

    override fun onCreate() {
        super.onCreate()
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            LifecycleEventObserver { _, event -> onProcessEvent(event) },
        )
    }

    /** Builds the Studio if it doesn't exist yet. Main thread only: the
     * Studio is single-threaded, and this reads disk, so call it after the
     * first frame. */
    fun buildStudio(): Studio {
        check(Looper.myLooper() == Looper.getMainLooper()) { "buildStudio off the main thread" }
        studio?.let { return it }
        val core = ChipCore(AudioRate.native(this))
        val output = AndroidAudioOutput(this, core)
        val prefs = SharedPrefsKeyValueStore(this)
        val exportDir = File(cacheDir, ShareRoots.EXPORT)
        val videoWriter = Mp4Writer(resources)
        val built = Studio(
            store = FileSongStore(File(filesDir, "Songs"), prefs),
            audio = output,
            scheduler = AndroidScheduler(),
            renderer = { ExportRenderer.render(it, exportDir, videoWriter) },
            exportExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "chiptune-export") },
            shareWriter = SongShareWriter(File(cacheDir, ShareRoots.SHARE)),
            core = core,
            keepAlive = exportKeepAlive,
        )
        output.events = object : AudioOutputEvents {
            override fun onAudioFocusLost() = built.onAudioFocusLost()
            override fun onAudioFocusGained() = built.onAudioFocusGained()
            override fun onBecomingNoisy() = built.onBecomingNoisy()
            override fun onAudioOutputDead() = built.onAudioOutputDead()
        }
        studio = built
        return built
    }

    /** iOS's scenePhase handler: any phase but ACTIVE saves, BACKGROUND
     * also stops the engine. ProcessLifecycleOwner reports ON_PAUSE/ON_STOP
     * about 700 ms after the last activity goes, so a rotation doesn't count. */
    private fun onProcessEvent(event: Lifecycle.Event) {
        val phase = AppPhase.fromLifecycleEvent(event.name) ?: return
        val studio = studio ?: return
        if (ScenePhasePolicy.savesNow(phase)) studio.saveNow()
        if (ScenePhasePolicy.stopsEngine(phase)) studio.stopEngineForBackground()
    }
}
