package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.ExportRequest
import dev.individuation.chiptune.core.audio.ExportResult
import dev.individuation.chiptune.core.audio.ExportRenderer
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.store.FileSongStore
import dev.individuation.chiptune.core.store.InMemoryKeyValueStore
import java.io.File
import java.nio.file.Files
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.junit.Assert.fail

/** A [Scheduler] the test drives by hand: time only moves on [advance], and
 * work posted from other threads only runs on [runPosted]. No real sleeps. */
class ManualScheduler(var time: Double = 0.0) : Scheduler {
    private class Task(var dueAt: Double, val interval: Double?, val action: () -> Unit) {
        var cancelled = false
    }

    private val tasks = ArrayList<Task>()
    private val posted = ConcurrentLinkedQueue<() -> Unit>()

    override fun now(): Double = time

    override fun schedule(delaySeconds: Double, action: () -> Unit): Cancellable {
        val task = Task(time + delaySeconds, null, action)
        tasks.add(task)
        return Cancellable { task.cancelled = true }
    }

    override fun scheduleRepeating(intervalSeconds: Double, action: () -> Unit): Cancellable {
        val task = Task(time + intervalSeconds, intervalSeconds, action)
        tasks.add(task)
        return Cancellable { task.cancelled = true }
    }

    override fun post(action: () -> Unit) {
        posted.add(action)
    }

    /** Runs whatever other threads have posted, in order. */
    fun runPosted(): Int {
        var n = 0
        while (true) {
            val action = posted.poll() ?: break
            action()
            n += 1
        }
        return n
    }

    /** Timers still armed. */
    val pendingTimers: Int get() = tasks.count { !it.cancelled }

    /** Moves the clock on, firing every timer that comes due on the way. */
    fun advance(seconds: Double) {
        val end = time + seconds
        while (true) {
            tasks.removeAll { it.cancelled }
            val next = tasks.filter { it.dueAt <= end }.minByOrNull { it.dueAt } ?: break
            time = maxOf(time, next.dueAt)
            if (next.interval == null) {
                tasks.remove(next)
            } else {
                next.dueAt += next.interval
            }
            next.action()
        }
        time = end
    }
}

/** An output that starts (or refuses to) on command, and counts what was asked of it. */
class FakeAudioOutput : AudioOutput {
    var startSucceeds = true
    var failure: Throwable? = null
    var starts = 0
    var rebuilds = 0
    override var isRunning = false
    override var lastError: Throwable? = null

    override fun startIfNeeded(): Boolean {
        if (isRunning) return true
        starts += 1
        if (!startSucceeds) {
            lastError = failure
            return false
        }
        isRunning = true
        lastError = null
        return true
    }

    override fun stopEngine() {
        isRunning = false
    }

    override fun rebuild() {
        rebuilds += 1
        isRunning = false
    }
}

/** A [FileSongStore] on a throwaway directory with its own preferences. */
class TempStore {
    val directory: File = Files.createTempDirectory("chiptune-tests-").toFile()
    val prefs = InMemoryKeyValueStore()
    val store = FileSongStore(directory, prefs)

    fun save(song: Song, makeCurrent: Boolean = false) {
        store.save(song, makeCurrent)
    }

    fun clean() {
        directory.setWritable(true)
        directory.walkTopDown().forEach { it.setWritable(true) }
        directory.deleteRecursively()
    }
}

/** Everything a [Studio] needs, faked or on temp folders. Autosave is off by
 * default: a live timer would make editing tests order-dependent. */
class StudioHarness(
    val temp: TempStore = TempStore(),
    autosaveEnabled: Boolean = false,
    renderer: ((ExportRequest) -> ExportResult)? = null,
    keepAlive: ExportKeepAlive = ExportKeepAlive.None,
    val exportDir: File = Files.createTempDirectory("chiptune-export-").toFile(),
) {
    val scheduler = ManualScheduler()
    val audio = FakeAudioOutput()
    val shareDir: File = Files.createTempDirectory("chiptune-share-").toFile()
    val executor: ExecutorService = Executors.newSingleThreadExecutor()
    val studio = Studio(
        store = temp.store,
        audio = audio,
        scheduler = scheduler,
        autosaveEnabled = autosaveEnabled,
        renderer = renderer ?: { ExportRenderer.render(it, exportDir) },
        exportExecutor = executor,
        shareWriter = SongShareWriter(shareDir),
        keepAlive = keepAlive,
        exportDirectory = exportDir,
    )

    /** Waits for everything queued on the export executor so far. */
    fun drainExecutor() {
        executor.submit {}.get(10, java.util.concurrent.TimeUnit.SECONDS)
    }

    /** Pumps posted work until the export finishes (Swift's `waitForExport`). */
    fun waitForExport(timeoutSeconds: Double = 60.0) {
        val deadline = System.nanoTime() + (timeoutSeconds * 1e9).toLong()
        while (true) {
            scheduler.runPosted()
            if (!studio.isExporting) return
            if (System.nanoTime() > deadline) fail("export never finished")
            Thread.sleep(2)
        }
    }

    fun close() {
        studio.invalidateTimers()
        executor.shutdownNow()
        temp.clean()
        exportDir.deleteRecursively()
        shareDir.deleteRecursively()
    }
}

/** `studio.song.x = y` for the immutable model. */
fun Studio.edit(transform: (Song) -> Song) {
    song = transform(song)
}

fun Song.withSection(index: Int, transform: (SongSection) -> SongSection): Song =
    copy(arrangement = arrangement.mapIndexed { i, s -> if (i == index) transform(s) else s })

/** Swift's `Int((sampleRate * 60 / (tempo * 4)).rounded())`. */
fun samplesPerStep(tempo: Double): Int =
    dev.individuation.chiptune.core.model.swiftRounded(44100.0 * 60.0 / (tempo * 4.0)).toInt()
