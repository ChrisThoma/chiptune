import AVFoundation

/// Wraps AVAudioEngine and feeds it from `ChipCore`.
final class AudioEngine {
    let core: ChipCore

    /// Replaced wholesale when the media server restarts — every node in a
    /// graph is invalid after that, so the graph is rebuilt rather than patched.
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var running = false

    /// Why the last `startIfNeeded()` failed, for the UI to show. The engine
    /// stays UI-free; this is a value the caller reads, not a message it prints.
    private(set) var lastError: Error?

    private static let sampleRate = 44100.0
    private static let scratchLength = 4096

    /// Sized for the largest render slice we expect. Owned by the engine rather
    /// than by the graph so rebuilding the graph doesn't leak one buffer per
    /// rebuild — the render callback captures this pointer and must not
    /// allocate, so it can't be created per-callback either.
    private let scratch: UnsafeMutablePointer<Float>

    init() {
        core = ChipCore(sampleRate: AudioEngine.sampleRate)
        scratch = .allocate(capacity: AudioEngine.scratchLength)
        scratch.initialize(repeating: 0, count: AudioEngine.scratchLength)
        buildEngine()
    }

    deinit {
        scratch.deallocate()
    }

    /// Builds a fresh engine and source node around the existing core.
    ///
    /// Called once at init, and again when the system tells us the media
    /// services were reset: at that point every node, and the engine itself,
    /// is dead, and nothing short of a new graph brings audio back.
    func buildEngine() {
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
        }
        running = false

        let engine = AVAudioEngine()
        // Can't fail for 44100/2 — but "no crashes in the audio path" is a
        // property, not a bet. A nil format leaves the graph unbuilt, and
        // `startIfNeeded` reports that instead of starting silence.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioEngine.sampleRate,
                                         channels: 2) else {
            sourceNode = nil
            lastError = NSError(domain: "Chiptune.AudioEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The audio format could not be created."
            ])
            return
        }
        let core = self.core
        let scratch = self.scratch
        let scratchLength = AudioEngine.scratchLength

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            AudioEngine.fill(audioBufferList, frames: Int(frameCount),
                             from: core, scratch: scratch, scratchLen: scratchLength)
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        self.engine = engine
        self.sourceNode = node
    }

    /// Fills every buffer in a Core Audio buffer list from the core, rendering
    /// in scratch-sized slices. Core Audio can ask for more frames than the
    /// scratch holds (larger IO buffers when the screen locks, for one), so
    /// this loops until the whole request is filled — dropping the excess
    /// would lose audio and let the sequencer clock drift. Runs on the render
    /// thread, so it must not allocate.
    static func fill(_ audioBufferList: UnsafeMutablePointer<AudioBufferList>,
                     frames total: Int,
                     from core: ChipCore,
                     scratch: UnsafeMutablePointer<Float>,
                     scratchLen: Int) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var done = 0
        while done < total {
            let n = min(total - done, scratchLen)
            core.render(frames: n, into: scratch)
            for buffer in abl {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<n { data[done + i] = scratch[i] }
            }
            done += n
        }
    }

    /// Configures the session and starts the engine. Safe to call repeatedly.
    ///
    /// - Returns: whether audio is running. A caller that flips a PLAY button
    ///   on the strength of this must check it — the button going green over
    ///   silence is worse than an error.
    @discardableResult
    func startIfNeeded() -> Bool {
        guard !running else { return true }
        // A failed `buildEngine` leaves no source node; starting the engine
        // anyway would "succeed" into silence, wiping the error it recorded.
        guard sourceNode != nil else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            running = true
            lastError = nil
            return true
        } catch {
            lastError = error
            running = false
            return false
        }
    }

    func stopEngine() {
        guard running else { return }
        engine.stop()
        running = false
    }

    var isRunning: Bool { running }
}
