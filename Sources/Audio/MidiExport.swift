import Foundation

/// Writes a song out as a Standard MIDI File, for taking the notes into a DAW.
///
/// Format 1 at 96 ticks per quarter: track 0 is the conductor (name, tempo,
/// meter), then one MIDI track per chip track in song order. The Android port
/// writes the same bytes from the same song, and the golden files in
/// `Tests/Fixtures/midi-*.mid` hold both to that.
enum MidiExport {
    /// 96 divides into a sixteenth evenly, which is all the sequencer can
    /// place a note on.
    static let ticksPerQuarter = 96
    static let ticksPerStep = ticksPerQuarter / Chip.stepsPerBeat

    /// The file's bytes. Normalizes first, as the WAV export does, so a song
    /// straight from a file can't put an out-of-range tempo into the header.
    static func data(for song: Song) -> Data {
        var song = song
        song.normalize()
        let endTick = song.arrangementSteps * ticksPerStep

        var file = Data()
        file.append(contentsOf: Array("MThd".utf8))
        file.append(be32(6))
        file.append(be16(1))
        file.append(be16(song.tracks.count + 1))
        file.append(be16(ticksPerQuarter))

        file.append(chunk(conductor(for: song, endTick: endTick)))
        let channels = channels(for: song.tracks)
        let audibleDrums = song.tracks.contains { $0.kind == .noise && !$0.muted }
        for index in song.tracks.indices {
            file.append(chunk(track(index, of: song, channel: channels[index],
                                    audibleDrums: audibleDrums, endTick: endTick)))
        }
        return file
    }

    /// GM's drum channel, "channel 10" to a person.
    static let drumChannel: UInt8 = 9

    /// Melodic tracks count up from channel 0 in song order; every noise track
    /// goes to the drum channel. Eight tracks at most, so the count never
    /// reaches 9, but it skips it all the same rather than trust that.
    private static func channels(for tracks: [Track]) -> [UInt8] {
        var next: UInt8 = 0
        return tracks.map { track in
            guard track.kind != .noise else { return drumChannel }
            if next == drumChannel { next += 1 }
            defer { next += 1 }
            return next
        }
    }

    /// GM programs, counted from zero: 81 "Lead 1 (square)" for the pulses
    /// and 39 "Synth Bass 1" for the triangle, which is where a song's bass
    /// lives. Noise is on the drum channel, where a program picks a kit.
    private static func program(for kind: ChannelKind) -> UInt8? {
        switch kind {
        case .pulse1, .pulse2: return 80
        case .triangle: return 38
        case .noise: return nil
        }
    }

    /// GM percussion keys for the noise presets, by preset name.
    private static let presetDrums: [String: UInt8] = [
        "Kick": 36, "Snare": 38, "Hat": 46, "Closed hat": 42, "Crash": 49,
    ]

    /// Which drum each note on a noise track plays.
    ///
    /// A track still on a preset plays that preset's drum for every note,
    /// whatever pitch it was written at. A custom one is spread over kick,
    /// snare and closed hat by where each note sits among the track's own
    /// distinct notes, lowest to highest. It has to be relative: the library
    /// songs write their noise between 52 and 71, so fixed pitch ranges would
    /// make nearly everything a snare. Only the notes the arrangement plays
    /// count, so an unplayed pattern can't move the bands.
    private static func drumMap(for index: Int, of song: Song) -> (Int8) -> UInt8 {
        let instrument = song.tracks[index].instrument
        if let preset = InstrumentPreset.matching(instrument, kind: .noise),
           let drum = presetDrums[preset.name] {
            return { _ in drum }
        }
        let distinct = Set(song.chain.flatMap { song.patterns[$0].rows[index].prefix(song.patterns[$0].length) }
            .filter { $0 >= 0 }).sorted()
        let bands: [UInt8] = [36, 38, 42]
        var drums: [Int8: UInt8] = [:]
        for (i, note) in distinct.enumerated() {
            // A lone note takes the middle band, a snare, not the bottom one.
            drums[note] = distinct.count == 1 ? 38 : bands[i * 3 / distinct.count]
        }
        // Every note the track plays was counted above; the fallback is
        // only there so a lookup can't trap.
        return { drums[$0] ?? 38 }
    }

    /// The longest a drum hit is held. GM drums are one-shots, so the length
    /// only matters for one thing: every noise track shares the drum channel,
    /// and an off landing on the tick where another track starts the same
    /// drum leaves the result to however a DAW orders the merge. A tick short
    /// of a step can never meet another note's on.
    private static let maxDrumTicks = ticksPerStep - 1

    /// One chip track's MIDI track. `audibleDrums` says whether
    /// any noise track in the song is unmuted, which decides how a muted
    /// noise track can be silenced.
    private static func track(_ index: Int, of song: Song, channel: UInt8,
                              audibleDrums: Bool, endTick: Int) -> TrackEvents {
        let track = song.tracks[index]
        let instrument = track.instrument
        let isDrum = track.kind == .noise
        let pitch = isDrum ? drumMap(for: index, of: song) : { UInt8($0) }

        // A muted track is written in full, so unmuting it in a DAW brings
        // the part back, but silenced with its channel's volume. A muted noise
        // track can't do that when an audible one shares the drum channel, so
        // it goes as quiet as a note can instead.
        let silenceChannel = track.muted && !(isDrum && audibleDrums)
        let quietNotes = track.muted && !silenceChannel

        // Volume goes into the velocity rather than a CC7, because the noise
        // tracks share one channel and one channel has one volume. Never 0,
        // which a note-on would read as a note-off.
        let velocity = quietNotes ? 1 : UInt8(max(1, Int((instrument.volume * 127).rounded())))
        // How long a decaying note is heard, in ticks. `decay` is the time to
        // -60 dB, which is where the synth's own envelope gives out.
        let decayTicks = max(1, Int((instrument.decay * song.tempo / 60 * Double(ticksPerQuarter)).rounded()))

        var events = TrackEvents()
        let label = song.fullLabel(for: index)
        events.append(at: 0, text(0x03, track.muted ? "\(label) (muted)" : label))
        if let program = program(for: track.kind) {
            events.append(at: 0, [0xC0 | channel, program])
        }
        if silenceChannel {
            events.append(at: 0, [0xB0 | channel, 0x07, 0x00])
        }

        // The note still sounding, and the tick its decay would end it by.
        var sounding: (note: UInt8, endsBy: Int)?
        func release(at tick: Int) {
            guard let held = sounding else { return }
            // A decayed note was already silent before whatever ends it now;
            // its off goes where the sound stopped. Writing it late here keeps
            // the list in order, since that tick is past the note's own on.
            // Release velocity 64 is the spec's "no release velocity" value.
            events.append(at: min(held.endsBy, tick), [0x80 | channel, held.note, 0x40])
            sounding = nil
        }

        // `chain` is exactly what playback walks, repeats expanded and capped,
        // so a held note carries over a pattern boundary just as
        // `ChipCore.triggerStep` lets it.
        var tick = 0
        for patternIndex in song.chain {
            let pattern = song.patterns[patternIndex]
            for step in 0..<pattern.length {
                let cell = pattern.rows[index][step]
                if cell == Chip.noteOff {
                    release(at: tick)
                } else if cell >= 0 {
                    // Off before on, so a repeated pitch retriggers instead of
                    // being started and then ended at the same instant.
                    release(at: tick)
                    let note = pitch(cell)
                    events.append(at: tick, [0x90 | channel, note, velocity])
                    var endsBy = instrument.sustain ? Int.max : tick + decayTicks
                    if isDrum { endsBy = min(endsBy, tick + maxDrumTicks) }
                    sounding = (note, endsBy)
                }
                tick += ticksPerStep
            }
        }
        release(at: endTick)
        // Every track ends on the last tick, sounding or not, so the file
        // loops at the arrangement's length in a DAW.
        events.append(at: endTick, [0xFF, 0x2F, 0x00])
        return events
    }

    private static func conductor(for song: Song, endTick: Int) -> TrackEvents {
        var events = TrackEvents()
        events.append(at: 0, text(0x03, song.name))
        let micros = Int((60_000_000 / song.tempo).rounded())
        events.append(at: 0, [0xFF, 0x51, 0x03,
                              UInt8(micros >> 16 & 0xFF), UInt8(micros >> 8 & 0xFF), UInt8(micros & 0xFF)])
        // 4/4; a click every 24 MIDI clocks (one quarter); eight 32nds to the
        // quarter. The app has no meter of its own, and four sixteenths to the
        // beat reads naturally as 4/4.
        events.append(at: 0, [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])
        events.append(at: endTick, [0xFF, 0x2F, 0x00])
        return events
    }

    // MARK: Bytes

    /// A track's events at absolute ticks, appended in the order they are to
    /// be written. Deltas are worked out on the way to bytes, so a caller
    /// never has to.
    private struct TrackEvents {
        private(set) var items: [(tick: Int, bytes: [UInt8])] = []

        mutating func append(at tick: Int, _ bytes: [UInt8]) {
            items.append((tick, bytes))
        }
    }

    private static func chunk(_ events: TrackEvents) -> Data {
        var body: [UInt8] = []
        var last = 0
        for item in events.items {
            body += vlq(item.tick - last)
            body += item.bytes
            last = item.tick
        }
        var out = Data(Array("MTrk".utf8))
        out.append(be32(body.count))
        out.append(contentsOf: body)
        return out
    }

    /// A text meta event. The length is the UTF-8 byte count, not the
    /// character count: one non-ASCII letter in a name would otherwise cut
    /// the end off it, or swallow the next event's first byte.
    private static func text(_ type: UInt8, _ string: String) -> [UInt8] {
        let bytes = Array(string.utf8)
        return [0xFF, type] + vlq(bytes.count) + bytes
    }

    private static func vlq(_ value: Int) -> [UInt8] {
        var out = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            out.insert(UInt8(rest & 0x7F | 0x80), at: 0)
            rest >>= 7
        }
        return out
    }

    private static func be16(_ value: Int) -> Data {
        Data([UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    private static func be32(_ value: Int) -> Data {
        Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
              UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}
