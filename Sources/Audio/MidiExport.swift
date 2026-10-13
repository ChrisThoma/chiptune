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
        for _ in song.tracks.indices {
            var events = TrackEvents()
            events.append(at: 0, [0xFF, 0x2F, 0x00])
            file.append(chunk(events))
        }
        return file
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
