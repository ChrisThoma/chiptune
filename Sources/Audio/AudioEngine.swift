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
            let frames = min(Int(frameCount), 4096)
            core.render(frames: frames, into: scratch)

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in abl {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<frames { data[i] = scratch[i] }
                // Silence anything past what we rendered.
                if Int(frameCount) > frames {
                    for i in frames..<Int(frameCount) { data[i] = 0 }
                }
            }
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
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
