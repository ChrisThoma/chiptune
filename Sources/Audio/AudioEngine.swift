import AVFoundation

/// Wraps AVAudioEngine and feeds it from `ChipCore`.
final class AudioEngine {
    let core: ChipCore
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var running = false

    init() {
        let sampleRate = 44100.0
        core = ChipCore(sampleRate: sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let core = self.core
        // Scratch buffer sized for the largest render slice we expect; the
        // callback must not allocate, so it is created once here.
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
        scratch.initialize(repeating: 0, count: 4096)

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            AudioEngine.fill(audioBufferList, frames: Int(frameCount),
                             from: core, scratch: scratch, scratchLen: 4096)
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
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
    func startIfNeeded() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    func stopEngine() {
        guard running else { return }
        engine.stop()
        running = false
    }
}
