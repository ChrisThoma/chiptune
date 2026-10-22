import Foundation

/// How bright each track's bar is on a frame of the Cover style.
///
/// A note-on lights the bar fully on the frame its sound starts, and it fades
/// in a straight line to dark over `decayFrames`. A note-off cuts it, as it
/// cuts the sound. A track that is heard as nothing — muted, or at a volume
/// the MIDI export would also call silent (`MidiExport.isSilent`) — never
/// lights, so the bars only move for music the soundtrack actually plays.
///
/// The fade is fixed rather than following each instrument's decay: a
/// triangle held for four seconds would otherwise sit at full brightness and
/// stop reading as a beat.
struct ChannelPulse {
    /// A third of a second at 30 fps.
    static let decayFrames = 10

    private let timeline: VideoTimeline
    private let patterns: [Pattern]
    private let silent: [Bool]

    init(song: Song, timeline: VideoTimeline) {
        var song = song
        song.normalize()
        self.timeline = timeline
        patterns = song.patterns
        silent = song.tracks.map(MidiExport.isSilent)
    }

    /// How many of a bar's `count` segments `level` lights: any level lights
    /// the bottom one, and the count rounds up so a note's first frames
    /// light the whole bar.
    static func litSegments(level: Double, of count: Int) -> Int {
        guard level > 0 else { return 0 }
        return min(count, Int((level * Double(count)).rounded(.up)))
    }

    /// One level per track, 0...1.
    func levels(frame: Int) -> [Double] {
        silent.indices.map { level(track: $0, frame: frame) }
    }

    private func level(track: Int, frame: Int) -> Double {
        guard !silent[track], timeline.samplesPerStep > 0 else { return 0 }
        let now = timeline.sample(frame: frame)
        let lastStep = timeline.stepsPerPass * timeline.loopCount - 1
        // Past the body the last step is still the latest thing played, so a
        // note on it carries on fading through the tail.
        var step = min(now / timeline.samplesPerStep, lastStep)
        while step >= 0 {
            let since = Double(now - step * timeline.samplesPerStep) / Double(VideoTimeline.samplesPerFrame)
            guard since < Double(Self.decayFrames) else { return 0 }
            if let at = timeline.position(globalStep: step),
               let note = patterns[safe: at.pattern]?.rows[safe: track]?[safe: at.step] {
                if note >= 0 { return 1 - since / Double(Self.decayFrames) }
                if note == Chip.noteOff { return 0 }
            }
            step -= 1
        }
        return 0
    }
}
