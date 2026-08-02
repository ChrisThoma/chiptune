import Foundation

/// Fixed limits shared by the DSP core and the UI. The audio thread indexes
/// into flat buffers sized from these, so they must not change at runtime.
///
/// A song uses 1...`maxTracks` tracks and picks a channel kind per track, so
/// the same kind can appear more than once — two triangles, three pulses, and
/// so on. A track index is *not* a `ChannelKind`; the track carries its kind.
///
/// Notes live in patterns rather than on the track, and the arrangement chains
/// patterns into a song. A track is a *voice*: its sound and its mute state.
enum Chip {
    static let maxTracks = 8
    static let maxSteps = 64
    static let maxPatterns = 16
    /// Sections expand into a flat list of pattern slots for the audio thread;
    /// this caps that list, not the number of sections the UI shows.
    static let maxChain = 128
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

    /// Widest arpeggio offset a file may declare, in semitones — four octaves
    /// either way, far past anything musical and far short of anything that
    /// overflows the frequency maths.
    static let maxArpeggioSemitones = 48
    /// The core reads at most this many offsets; the rest are dead weight.
    static let maxArpeggioSteps = 4

    /// Forces every field back into the range the synth can actually play.
    ///
    /// The UI can't produce a bad instrument — its controls are all bounded —
    /// but a `.chipsong` file is arbitrary JSON from wherever the user got it,
    /// and the numbers here reach the DSP directly. An unclamped arpeggio
    /// offset is the sharp edge: `pow(2, semitones / 12)` goes to infinity, the
    /// voice's phase increment becomes infinite, its output becomes NaN, and
    /// the master DC blocker feeds that NaN back into itself forever — one bad
    /// file and the app is silent until it's relaunched.
    mutating func normalize() {
        duty = min(max(duty, 0), Instrument.dutyCycles.count - 1)
        volume = volume.isFinite ? min(max(volume, 0), 1) : 0.8
        decay = decay.isFinite ? min(max(decay, 0.01), 4.0) : 0.35
        arpeggio = arpeggio.prefix(Instrument.maxArpeggioSteps).map {
            min(max($0, -Instrument.maxArpeggioSemitones), Instrument.maxArpeggioSemitones)
        }
    }

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

    /// Notes read out of a file written before patterns existed. `Song`'s
    /// decoder folds them into pattern A and clears this; it is never encoded.
    var legacyNotes: [Int8]?

    init(kind: ChannelKind) {
        self.kind = kind
        self.instrument = .default(for: kind)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, instrument, muted, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Songs saved before tracks were addable have no id of their own.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ChannelKind.self, forKey: .kind)
        instrument = try c.decode(Instrument.self, forKey: .instrument)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        legacyNotes = try c.decodeIfPresent([Int8].self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(instrument, forKey: .instrument)
        try c.encode(muted, forKey: .muted)
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
            && lhs.instrument == rhs.instrument && lhs.muted == rhs.muted
    }
}

/// A block of steps — one row per track. Patterns are the unit the grid edits
/// and the unit the arrangement chains together.
struct Pattern: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// Short display name, "A" through "P" by default.
    var name: String = "A"
    /// Steps in this pattern, 4...64. Patterns need not be the same length.
    var length: Int = 16
    /// One row per track, each `Chip.maxSteps` long; `Chip.emptyNote` for a rest.
    var rows: [[Int8]] = []

    init(name: String, length: Int = 16, trackCount: Int) {
        self.name = name
        self.length = length
        self.rows = Array(repeating: Pattern.emptyRow, count: max(trackCount, 1))
    }

    static var emptyRow: [Int8] { Array(repeating: Chip.emptyNote, count: Chip.maxSteps) }

    var isEmpty: Bool {
        rows.allSatisfy { $0.allSatisfy { $0 == Chip.emptyNote } }
    }

    /// Pads or trims decoded rows so an older or corrupt file can't send the
    /// audio thread past the end of its fixed-size buffers.
    mutating func normalize(trackCount: Int) {
        length = min(max(length, 4), Chip.maxSteps)
        let want = max(trackCount, 1)
        if rows.count < want {
            rows.append(contentsOf: Array(repeating: Pattern.emptyRow, count: want - rows.count))
        } else if rows.count > want {
            rows = Array(rows.prefix(want))
        }
        for i in rows.indices {
            if rows[i].count < Chip.maxSteps {
                rows[i].append(contentsOf: Array(repeating: Chip.emptyNote,
                                                 count: Chip.maxSteps - rows[i].count))
            } else if rows[i].count > Chip.maxSteps {
                rows[i] = Array(rows[i].prefix(Chip.maxSteps))
            }
            // Cell values too: anything that isn't a rest, a note-off, or a
            // MIDI note would draw as a filled cell with a garbage label while
            // the audio engine ignores it.
            for s in rows[i].indices {
                let n = rows[i][s]
                if n != Chip.emptyNote, n != ChipCore.noteOff, !(0...127).contains(n) {
                    rows[i][s] = Chip.emptyNote
                }
            }
        }
    }
}

/// One entry in the arrangement: play this pattern this many times.
struct SongSection: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var patternID: UUID
    var repeats: Int = 1

    static let maxRepeats = 16
}

struct Song: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "Untitled"
    var tempo: Double = 120
    var tracks: [Track]
    var patterns: [Pattern]
    /// Play order. An empty arrangement is not representable — `normalize`
    /// falls back to playing the first pattern once.
    var arrangement: [SongSection]
    var modified: Date = Date()

    init(name: String = "Untitled") {
        self.name = name
        let tracks = ChannelKind.allCases.map { Track(kind: $0) }
        let pattern = Pattern(name: "A", length: 16, trackCount: tracks.count)
        self.tracks = tracks
        self.patterns = [pattern]
        self.arrangement = [SongSection(patternID: pattern.id)]
    }

    var stepsPerBeat: Int { 4 }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case id, name, tempo, tracks, patterns, arrangement, modified
        /// Pre-arrangement files kept a single pattern length on the song.
        case length
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        tempo = try c.decodeIfPresent(Double.self, forKey: .tempo) ?? 120
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        tracks = try c.decode([Track].self, forKey: .tracks)

        if let saved = try c.decodeIfPresent([Pattern].self, forKey: .patterns), !saved.isEmpty {
            patterns = saved
            arrangement = try c.decodeIfPresent([SongSection].self, forKey: .arrangement) ?? []
        } else {
            // Written before patterns existed: the tracks' own note arrays are
            // the whole song, so they become pattern A.
            var first = Pattern(name: "A",
                                length: try c.decodeIfPresent(Int.self, forKey: .length) ?? 16,
                                trackCount: tracks.count)
            for (i, track) in tracks.enumerated() {
                if let notes = track.legacyNotes, i < first.rows.count { first.rows[i] = notes }
            }
            patterns = [first]
            arrangement = [SongSection(patternID: first.id)]
        }
        for i in tracks.indices { tracks[i].legacyNotes = nil }
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(tempo, forKey: .tempo)
        try c.encode(tracks, forKey: .tracks)
        try c.encode(patterns, forKey: .patterns)
        try c.encode(arrangement, forKey: .arrangement)
        try c.encode(modified, forKey: .modified)
    }

    // MARK: Invariants

    mutating func normalize() {
        // Not just a clamp: `min`/`max` pass NaN straight through, and the
        // sequencer converts the tempo to an Int32 sample count — which traps
        // on a NaN rather than merely sounding wrong.
        tempo = tempo.isFinite ? min(max(tempo, 40), 300) : 120
        if tracks.isEmpty { tracks = ChannelKind.allCases.map { Track(kind: $0) } }
        if tracks.count > Chip.maxTracks { tracks = Array(tracks.prefix(Chip.maxTracks)) }
        for i in tracks.indices { tracks[i].instrument.normalize() }

        if patterns.isEmpty { patterns = [Pattern(name: "A", length: 16, trackCount: tracks.count)] }
        if patterns.count > Chip.maxPatterns { patterns = Array(patterns.prefix(Chip.maxPatterns)) }
        for i in patterns.indices { patterns[i].normalize(trackCount: tracks.count) }

        let known = Set(patterns.map(\.id))
        arrangement.removeAll { !known.contains($0.patternID) }
        for i in arrangement.indices {
            arrangement[i].repeats = min(max(arrangement[i].repeats, 1), SongSection.maxRepeats)
        }
        if arrangement.isEmpty { arrangement = [SongSection(patternID: patterns[0].id)] }
    }

    // MARK: Patterns

    var canAddPattern: Bool { patterns.count < Chip.maxPatterns }

    func patternIndex(id: UUID) -> Int? { patterns.firstIndex { $0.id == id } }

    /// First unused letter, so deleting B and adding again gives you B back.
    func nextPatternName() -> String {
        let taken = Set(patterns.map(\.name))
        for i in 0..<Chip.maxPatterns {
            let name = String(UnicodeScalar(UInt8(65 + i)))
            if !taken.contains(name) { return name }
        }
        return "\(patterns.count + 1)"
    }

    // MARK: Arrangement

    /// The arrangement flattened into pattern indices, one entry per play-through.
    /// This is what the audio thread walks.
    var chain: [Int] {
        var out: [Int] = []
        for section in arrangement {
            guard let index = patternIndex(id: section.patternID) else { continue }
            for _ in 0..<max(section.repeats, 1) where out.count < Chip.maxChain {
                out.append(index)
            }
        }
        return out.isEmpty ? [0] : out
    }

    /// Steps in one pass of the whole arrangement.
    var arrangementSteps: Int {
        chain.reduce(0) { $0 + (patterns[safe: $1]?.length ?? 0) }
    }

    /// Seconds for one pass of the arrangement, at the current tempo.
    var arrangementDuration: TimeInterval {
        Double(arrangementSteps) * 60.0 / (max(tempo, 1) * Double(stepsPerBeat))
    }

    // MARK: Track labels

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
