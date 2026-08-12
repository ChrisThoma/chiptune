import Foundation

/// Named starting points for a channel's sound.
///
/// Four numbers — duty, volume, decay, arpeggio — are a precise way to describe
/// a chip voice and a poor way to find one. These are the sounds people
/// actually reach for, and between them they demonstrate what each parameter
/// does far better than the labels on the sliders do.
///
/// `Instrument.default(for:)` is the first preset of each kind, so adding a
/// track and picking that track's first preset can't drift apart.
struct InstrumentPreset: Identifiable, Equatable {
    var name: String
    var kind: ChannelKind
    var instrument: Instrument

    var id: String { "\(kind.rawValue).\(name)" }

    /// Ordered: the first of each kind is what a new track of that kind gets.
    static let all: [InstrumentPreset] = [
        // Pulse 1 — the lead channel, so it leads with a lead.
        InstrumentPreset(name: "Lead", kind: .pulse1,
                         instrument: Instrument(duty: 2, volume: 0.8, decay: 0.35)),
        InstrumentPreset(name: "Blip", kind: .pulse1,
                         instrument: Instrument(duty: 0, volume: 0.75, decay: 0.08)),
        InstrumentPreset(name: "Pluck", kind: .pulse1,
                         instrument: Instrument(duty: 1, volume: 0.8, decay: 0.18)),
        InstrumentPreset(name: "Chord", kind: .pulse1,
                         instrument: Instrument(duty: 2, volume: 0.7, decay: 0.5,
                                                arpeggio: [0, 4, 7])),
        InstrumentPreset(name: "Pad (holds)", kind: .pulse1,
                         instrument: Instrument(duty: 3, volume: 0.55, decay: 1.2,
                                                sustain: true)),

        // Pulse 2 — the second voice, quieter so it sits under the first.
        InstrumentPreset(name: "Harmony", kind: .pulse2,
                         instrument: Instrument(duty: 1, volume: 0.6, decay: 0.5)),
        InstrumentPreset(name: "Echo", kind: .pulse2,
                         instrument: Instrument(duty: 0, volume: 0.45, decay: 0.9)),
        InstrumentPreset(name: "Stab", kind: .pulse2,
                         instrument: Instrument(duty: 2, volume: 0.65, decay: 0.12)),
        InstrumentPreset(name: "Fifths", kind: .pulse2,
                         instrument: Instrument(duty: 1, volume: 0.6, decay: 0.45,
                                                arpeggio: [0, 7])),

        // Triangle — the bass channel. None of these hold; that was the bug.
        InstrumentPreset(name: "Bass", kind: .triangle,
                         instrument: Instrument(duty: 2, volume: 0.9, decay: 1.5)),
        InstrumentPreset(name: "Sub", kind: .triangle,
                         instrument: Instrument(duty: 2, volume: 1.0, decay: 0.6)),
        InstrumentPreset(name: "Pluck bass", kind: .triangle,
                         instrument: Instrument(duty: 2, volume: 0.9, decay: 0.22)),
        InstrumentPreset(name: "Octaves", kind: .triangle,
                         instrument: Instrument(duty: 2, volume: 0.85, decay: 1.0,
                                                arpeggio: [0, 12])),
        InstrumentPreset(name: "Drone (holds)", kind: .triangle,
                         instrument: Instrument(duty: 2, volume: 0.8, decay: 1.5,
                                                sustain: true)),

        // Noise — percussion. Decay is the whole instrument here.
        InstrumentPreset(name: "Hat", kind: .noise,
                         instrument: Instrument(duty: 2, volume: 0.5, decay: 0.12)),
        InstrumentPreset(name: "Closed hat", kind: .noise,
                         instrument: Instrument(duty: 2, volume: 0.4, decay: 0.04)),
        InstrumentPreset(name: "Snare", kind: .noise,
                         instrument: Instrument(duty: 2, volume: 0.7, decay: 0.25)),
        InstrumentPreset(name: "Kick", kind: .noise,
                         instrument: Instrument(duty: 2, volume: 0.9, decay: 0.09)),
        InstrumentPreset(name: "Crash", kind: .noise,
                         instrument: Instrument(duty: 2, volume: 0.6, decay: 1.4)),
    ]

    static func presets(for kind: ChannelKind) -> [InstrumentPreset] {
        all.filter { $0.kind == kind }
    }

    /// The preset an instrument still matches exactly, or nil once it's been
    /// edited away from all of them — which is what the menu shows as "Custom".
    static func matching(_ instrument: Instrument, kind: ChannelKind) -> InstrumentPreset? {
        presets(for: kind).first { $0.instrument == instrument }
    }
}
