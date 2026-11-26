import Foundation

/// The key a song is written in. Only numbers notes on the piano: nothing is
/// snapped or blocked, so out-of-key notes stay one tap away.
///
/// Saved as `{"root": 0-11, "scale": "major"|"minor"}`. Android writes the
/// same shape, so the two apps open each other's songs.
struct MusicalKey: Codable, Equatable, Hashable {
    /// Pitch class of the tonic, 0 = C.
    var root: Int
    var scale: Scale

    enum Scale: String, Codable, CaseIterable {
        case major, minor

        /// Semitones above the root. Natural minor only: harmonic and melodic
        /// minor would raise notes a chiptune melody mostly doesn't use.
        var intervals: [Int] {
            switch self {
            case .major: [0, 2, 4, 5, 7, 9, 11]
            case .minor: [0, 2, 3, 5, 7, 8, 10]
            }
        }

        var shortName: String {
            switch self {
            case .major: "maj"
            case .minor: "min"
            }
        }

        var spokenName: String { rawValue }
    }

    init(root: Int, scale: Scale) {
        self.root = root
        self.scale = scale
    }

    private enum CodingKeys: String, CodingKey { case root, scale }

    /// A root outside an octave would mark the wrong keys rather than none,
    /// so it is refused here and `Song` drops the whole key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let root = try c.decode(Int.self, forKey: .root)
        guard (0...11).contains(root) else {
            throw DecodingError.dataCorruptedError(forKey: .root, in: c,
                                                   debugDescription: "root \(root) is not a pitch class")
        }
        self.root = root
        scale = try c.decode(Scale.self, forKey: .scale)
    }

    /// Pitch class of a MIDI note. The double modulo keeps negative notes in
    /// 0...11, where Swift's `%` would give a negative remainder.
    static func pitchClass(_ midi: Int) -> Int {
        ((midi % 12) + 12) % 12
    }

    /// 1...7 for a note in the scale, the root being 1; nil outside it.
    func degree(_ midi: Int) -> Int? {
        let offset = ((Self.pitchClass(midi) - root) % 12 + 12) % 12
        return scale.intervals.firstIndex(of: offset).map { $0 + 1 }
    }

    func contains(_ midi: Int) -> Bool {
        degree(midi) != nil
    }

    func isRoot(_ midi: Int) -> Bool {
        Self.pitchClass(midi) == root
    }

    private var rootName: String {
        NoteName.names[Self.pitchClass(root)]
    }

    /// "C maj", "F# min": fits the KEY button.
    var shortLabel: String { "\(rootName) \(scale.shortName)" }

    /// "C major": what VoiceOver reads.
    var spokenLabel: String { "\(rootName) \(scale.spokenName)" }
}

/// Text for the KEY button and the piano keys' VoiceOver values, kept out of
/// the view so it can be tested without walking the accessibility tree.
enum KeyMark {
    static func buttonLabel(_ key: MusicalKey?) -> String {
        key?.shortLabel ?? "KEY"
    }

    static func buttonValue(_ key: MusicalKey?) -> String {
        key?.spokenLabel ?? "none"
    }

    /// Nil for an out-of-key note, or when the song has no key.
    static func accessibilityValue(key: MusicalKey?, midi: Int) -> String? {
        guard let degree = key?.degree(midi) else { return nil }
        return degree == 1 ? "degree 1, root" : "degree \(degree)"
    }
}
