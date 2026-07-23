import Foundation

/// Fixed limits shared by the DSP core and the UI. The audio thread indexes
/// into a flat buffer of `maxTracks * maxSteps` bytes, so these must not
/// change at runtime.
///
/// A song uses 1...`maxTracks` tracks and picks a channel kind per track, so
/// the same kind can appear more than once — two triangles, three pulses, and
/// so on. A track index is *not* a `ChannelKind`; the track carries its kind.
enum Chip {
    static let maxTracks = 8
    static let maxSteps = 64
    static let emptyNote: Int8 = -1
}

enum ChannelKind: Int, Codable, CaseIterable {
    case pulse1, pulse2, triangle, noise

    var name: String {
        switch self {
        case .pulse1: return "PU1"
        case .pulse2: return "PU2"
        case .triangle: return "TRI"
        case .noise: return "NOI"
        }
    }

    var fullName: String {
        switch self {
        case .pulse1: return "Pulse 1"
        case .pulse2: return "Pulse 2"
        case .triangle: return "Triangle"
        case .noise: return "Noise"
        }
    }

    /// Only the pulse channels have a meaningful duty cycle.
    var hasDuty: Bool { self == .pulse1 || self == .pulse2 }
}

/// Per-channel voice settings. Deliberately small — a chiptune voice does not
/// need much beyond a duty cycle, a level and a decay.
struct Instrument: Codable, Equatable {
    /// Index into `Instrument.dutyCycles`.
    var duty: Int = 2
    /// 0...1 channel level.
    var volume: Double = 0.8
    /// Seconds for the amplitude envelope to fall to silence. 4.0 means "hold".
    var decay: Double = 0.35
    /// Semitone offsets cycled at ~60 Hz. Empty means no arpeggio.
    var arpeggio: [Int] = []

    static let dutyCycles: [Double] = [0.125, 0.25, 0.5, 0.75]
    static let dutyLabels = ["12%", "25%", "50%", "75%"]

    static func `default`(for kind: ChannelKind) -> Instrument {
        switch kind {
        case .pulse1: return Instrument(duty: 2, volume: 0.8, decay: 0.35)
        case .pulse2: return Instrument(duty: 1, volume: 0.6, decay: 0.5)
        case .triangle: return Instrument(duty: 2, volume: 0.9, decay: 4.0)
        case .noise: return Instrument(duty: 2, volume: 0.5, decay: 0.12)
        }
    }
}

struct Track: Codable, Equatable, Identifiable {
    /// Stable across insertion and deletion so per-track view state (an open
    /// editor sheet, say) doesn't jump to a neighbour when a track is removed.
    var id: UUID = UUID()
    var kind: ChannelKind
    var instrument: Instrument
    var muted: Bool = false
    /// One entry per step; `Chip.emptyNote` for a rest. Always `Chip.maxSteps` long.
    var notes: [Int8]

    init(kind: ChannelKind) {
        self.kind = kind
        self.instrument = .default(for: kind)
        self.notes = Array(repeating: Chip.emptyNote, count: Chip.maxSteps)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, instrument, muted, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Songs saved before tracks were addable have no id of their own.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ChannelKind.self, forKey: .kind)
        instrument = try c.decode(Instrument.self, forKey: .instrument)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        notes = try c.decode([Int8].self, forKey: .notes)
    }

    /// Pads or trims a decoded note array so older/corrupt files can't crash the
    /// audio thread's fixed-size buffer.
    mutating func normalizeNotes() {
        if notes.count < Chip.maxSteps {
            notes.append(contentsOf: Array(repeating: Chip.emptyNote, count: Chip.maxSteps - notes.count))
        } else if notes.count > Chip.maxSteps {
            notes = Array(notes.prefix(Chip.maxSteps))
        }
    }
}

struct Song: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "Untitled"
    var tempo: Double = 120
    /// Steps in the loop, 4...64.
    var length: Int = 16
    var tracks: [Track]
    var modified: Date = Date()

    init(name: String = "Untitled") {
        self.name = name
        self.tracks = ChannelKind.allCases.map { Track(kind: $0) }
    }

    var stepsPerBeat: Int { 4 }

    mutating func normalize() {
        length = min(max(length, 4), Chip.maxSteps)
        tempo = min(max(tempo, 40), 300)
        // Any mix of kinds is legal now; only the count and the note arrays are
        // load-bearing for the audio thread's fixed-size buffers.
        if tracks.isEmpty { tracks = ChannelKind.allCases.map { Track(kind: $0) } }
        if tracks.count > Chip.maxTracks { tracks = Array(tracks.prefix(Chip.maxTracks)) }
        for i in tracks.indices { tracks[i].normalizeNotes() }
    }

    var canAddTrack: Bool { tracks.count < Chip.maxTracks }

    /// Short column name. Duplicated kinds get a letter — "TRI", or "TRI A" and
    /// "TRI B". Letters rather than numbers, because "PU1 1" is a riddle.
    func label(for index: Int) -> String {
        guard let track = tracks[safe: index] else { return "" }
        guard let suffix = duplicateSuffix(for: index) else { return track.kind.name }
        return "\(track.kind.name) \(suffix)"
    }

    /// Spoken/title name — "Triangle B".
    func fullLabel(for index: Int) -> String {
        guard let track = tracks[safe: index] else { return "" }
        guard let suffix = duplicateSuffix(for: index) else { return track.kind.fullName }
        return "\(track.kind.fullName) \(suffix)"
    }

    /// "A", "B", "C"… by position among tracks of the same kind, or nil when
    /// it's the only one of its kind and needs no suffix.
    private func duplicateSuffix(for index: Int) -> String? {
        guard let track = tracks[safe: index] else { return nil }
        let sameKind = tracks.indices.filter { tracks[$0].kind == track.kind }
        guard sameKind.count > 1, let position = sameKind.firstIndex(of: index) else { return nil }
        // maxTracks is 8, so this never runs past "H".
        return String(UnicodeScalar(UInt8(65 + min(position, 25))))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Note naming

enum NoteName {
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// MIDI note number -> "C#4".
    static func label(_ midi: Int8) -> String {
        guard midi >= 0 else { return "" }
        let n = Int(midi)
        return "\(names[n % 12])\(n / 12 - 1)"
    }

    static func frequency(_ midi: Int8) -> Double {
        440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
    }

    static func isSharp(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(midi % 12)
    }
}
