import Foundation

/// Fixed limits shared by the DSP core and the UI. The audio thread indexes
/// into a flat buffer of `channelCount * maxSteps` bytes, so these must not
/// change at runtime.
enum Chip {
    static let channelCount = 4
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

struct Track: Codable, Equatable {
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
        // Guarantee exactly one track per channel, in channel order.
        var rebuilt: [Track] = []
        for kind in ChannelKind.allCases {
            if var existing = tracks.first(where: { $0.kind == kind }) {
                existing.normalizeNotes()
                rebuilt.append(existing)
            } else {
                rebuilt.append(Track(kind: kind))
            }
        }
        tracks = rebuilt
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
