import Foundation

/// A small Standard MIDI File reader, written from the SMF 1.0 spec and
/// nothing else, so the MIDI tests check the stored bytes rather than the
/// writer's own idea of them. It turns a file into each track's events at
/// their absolute ticks.
///
/// It is strict where the export promises to be: running status is a parse
/// error rather than something to tolerate, and every chunk has to end exactly
/// where its length says it does.
struct MidiBytes {
    enum Event: Equatable {
        case noteOn(channel: Int, note: Int, velocity: Int)
        case noteOff(channel: Int, note: Int, velocity: Int)
        case program(channel: Int, program: Int)
        case control(channel: Int, controller: Int, value: Int)
        case meta(type: Int, bytes: [UInt8])
    }

    struct Timed: Equatable {
        var tick: Int
        var event: Event
    }

    /// One sounding note: the note-on paired with the first note-off of the
    /// same pitch on the same channel after it.
    struct Note: Equatable {
        var channel: Int
        var note: Int
        var velocity: Int
        var on: Int
        var off: Int
    }

    enum ParseError: Error, Equatable {
        case truncated
        case badChunk(String)
        case runningStatus(offset: Int)
        case unsupportedStatus(UInt8)
        case chunkOverrun
    }

    let format: Int
    let declaredTrackCount: Int
    let division: Int
    let tracks: [[Timed]]

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var pos = 0

        func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard n >= 0, pos + n <= bytes.count else { throw ParseError.truncated }
            defer { pos += n }
            return bytes[pos..<pos + n]
        }
        func be(_ slice: ArraySlice<UInt8>) -> Int {
            slice.reduce(0) { $0 << 8 | Int($1) }
        }
        func chunk(_ id: String) throws -> Range<Int> {
            let tag = String(decoding: try take(4), as: UTF8.self)
            guard tag == id else { throw ParseError.badChunk(tag) }
            let length = be(try take(4))
            guard pos + length <= bytes.count else { throw ParseError.chunkOverrun }
            return pos..<pos + length
        }

        let header = try chunk("MThd")
        guard header.count == 6 else { throw ParseError.badChunk("MThd length \(header.count)") }
        format = be(try take(2))
        declaredTrackCount = be(try take(2))
        division = be(try take(2))

        var tracks: [[Timed]] = []
        while pos < bytes.count {
            let body = try chunk("MTrk")
            var events: [Timed] = []
            var tick = 0

            func vlq() throws -> Int {
                var value = 0
                for _ in 0..<4 {
                    guard pos < body.upperBound else { throw ParseError.chunkOverrun }
                    let b = bytes[pos]
                    pos += 1
                    value = value << 7 | Int(b & 0x7F)
                    if b & 0x80 == 0 { return value }
                }
                throw ParseError.badChunk("VLQ longer than four bytes")
            }
            func data() throws -> Int {
                guard pos < body.upperBound else { throw ParseError.chunkOverrun }
                defer { pos += 1 }
                return Int(bytes[pos])
            }

            while pos < body.upperBound {
                tick += try vlq()
                guard pos < body.upperBound else { throw ParseError.chunkOverrun }
                let status = bytes[pos]
                guard status & 0x80 != 0 else { throw ParseError.runningStatus(offset: pos) }
                pos += 1
                let channel = Int(status & 0x0F)
                let event: Event
                switch status & 0xF0 {
                case 0x80: event = .noteOff(channel: channel, note: try data(), velocity: try data())
                case 0x90: event = .noteOn(channel: channel, note: try data(), velocity: try data())
                case 0xB0: event = .control(channel: channel, controller: try data(), value: try data())
                case 0xC0: event = .program(channel: channel, program: try data())
                case 0xF0 where status == 0xFF:
                    let type = try data()
                    let length = try vlq()
                    guard pos + length <= body.upperBound else { throw ParseError.chunkOverrun }
                    event = .meta(type: type, bytes: Array(bytes[pos..<pos + length]))
                    pos += length
                default:
                    // The export writes nothing else; anything here is a bug
                    // in it, not something for the reader to skip politely.
                    throw ParseError.unsupportedStatus(status)
                }
                events.append(Timed(tick: tick, event: event))
            }
            guard pos == body.upperBound else { throw ParseError.chunkOverrun }
            tracks.append(events)
        }
        self.tracks = tracks
    }

    /// The chip tracks, without the conductor.
    var chipTracks: ArraySlice<[Timed]> { tracks.dropFirst() }

    static func metas(_ type: Int, in track: [Timed]) -> [[UInt8]] {
        track.compactMap {
            if case .meta(type, let bytes) = $0.event { return bytes }
            return nil
        }
    }

    /// The track's FF 03 name, decoded as UTF-8.
    static func name(of track: [Timed]) -> String? {
        metas(0x03, in: track).first.map { String(decoding: $0, as: UTF8.self) }
    }

    /// Notes in the order they start. A note-on with no matching note-off is
    /// returned with `off` of -1, which no assertion will mistake for a tick.
    static func notes(in track: [Timed]) -> [Note] {
        var open: [Int: Int] = [:]  // channel << 8 | note -> index into out
        var out: [Note] = []
        for timed in track {
            switch timed.event {
            case let .noteOn(channel, note, velocity):
                open[channel << 8 | note] = out.count
                out.append(Note(channel: channel, note: note, velocity: velocity, on: timed.tick, off: -1))
            case let .noteOff(channel, note, _):
                if let index = open.removeValue(forKey: channel << 8 | note) {
                    out[index].off = timed.tick
                }
            default:
                break
            }
        }
        return out
    }

    /// Writes `n` as a variable-length quantity, for building expected bytes
    /// by hand in the tests. Kept apart from the parser's own reading so a
    /// mistake can't cancel itself out.
    static func vlq(_ n: Int) -> [UInt8] {
        var groups = [UInt8(n & 0x7F)]
        var rest = n >> 7
        while rest > 0 {
            groups.insert(UInt8(rest & 0x7F) | 0x80, at: 0)
            rest >>= 7
        }
        return groups
    }
}
