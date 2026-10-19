import Foundation

/// Which step of the song each frame of an exported video shows.
///
/// Built from exactly what the WAV renderer plays from: the normalized song,
/// `Chip.samplesPerStep`, `song.chain` and the patterns' lengths. Frame `f`
/// shows the audio at sample `f × samplesPerFrame`, so a note's cell reaches
/// the playing row on the frame its sound starts, and the picture can't drift
/// from the soundtrack over a long song the way a seconds-based clock would.
///
/// The Android build has a twin of this, and both are held to
/// `Tests/Fixtures/video-timeline.json`.
struct VideoTimeline: Equatable {
    static let fps = 30
    /// 1470 at 44.1kHz: a whole number, so frames never accumulate rounding.
    static let samplesPerFrame = Int(WavExport.sampleRate) / fps

    /// Where in the arrangement a frame is.
    struct Position: Equatable {
        /// Index into `chain`: the arrangement with its repeats expanded, so
        /// the second play of a section is a slot of its own.
        var chainSlot: Int
        /// Index into `song.patterns`.
        var pattern: Int
        /// Step inside that pattern.
        var step: Int
    }

    let samplesPerStep: Int
    /// Pattern index per chain slot, as `Song.chain` gives it.
    let chain: [Int]
    /// Step count of each chain slot's pattern.
    let slotLengths: [Int]
    let loopCount: Int
    /// The arrangement's passes. Nothing new is triggered after this.
    let bodySamples: Int
    /// The ring-out after the body, or 0 when the export folds it into the
    /// start. Truncated the way the WAV renderer and Kotlin's `toInt()` do.
    let tailSamples: Int

    var totalSamples: Int { bodySamples + tailSamples }
    /// Enough frames to cover every sample: the last one may run up to a
    /// frame past the audio, never short of it.
    var totalFrames: Int { (totalSamples + Self.samplesPerFrame - 1) / Self.samplesPerFrame }
    var stepsPerPass: Int { slotLengths.reduce(0, +) }
    var seconds: Double { Double(totalSamples) / WavExport.sampleRate }

    init(song: Song, options: ExportOptions) {
        var song = song
        song.normalize()
        let options = options.clamped
        samplesPerStep = Chip.samplesPerStep(tempo: song.tempo, sampleRate: WavExport.sampleRate)
        chain = song.chain
        slotLengths = chain.map { song.patterns[safe: $0]?.length ?? 0 }
        loopCount = options.loopCount
        bodySamples = samplesPerStep * max(song.arrangementSteps, 1) * options.loopCount
        tailSamples = options.effectiveTailMode == .ringOut
            ? Int(WavExport.sampleRate * WavExport.tailSeconds(for: song))
            : 0
    }

    /// The first sample frame `frame` shows.
    func sample(frame: Int) -> Int { frame * Self.samplesPerFrame }

    /// Steps since the start of the body at `frame`, with the fraction of the
    /// current step. Keeps counting through the tail, so a scroll or a decay
    /// driven by it carries on smoothly past the last step.
    func elapsedSteps(frame: Int) -> Double {
        Double(sample(frame: frame)) / Double(max(samplesPerStep, 1))
    }

    /// The step `frame` shows, or nil once the body is over and only the
    /// tail is ringing.
    func position(frame: Int) -> Position? {
        let s = sample(frame: frame)
        guard s >= 0, s < bodySamples, samplesPerStep > 0 else { return nil }
        return position(globalStep: s / samplesPerStep)
    }

    /// The step `globalStep` steps into the body, across passes; nil outside
    /// the body.
    func position(globalStep: Int) -> Position? {
        let perPass = stepsPerPass
        guard globalStep >= 0, perPass > 0, globalStep < perPass * loopCount else { return nil }
        var step = globalStep % perPass
        for (slot, length) in slotLengths.enumerated() {
            if step < length { return Position(chainSlot: slot, pattern: chain[slot], step: step) }
            step -= length
        }
        return nil
    }
}
