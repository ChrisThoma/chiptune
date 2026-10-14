import XCTest
@testable import Chiptune

/// Songs exported to `Tests/Fixtures/midi-*.mid` and compared byte for byte.
///
/// Like `GoldenRenderTests`, these are change detectors, not the oracle: the
/// `MidiExport*Tests` suites check the spec from hand-worked expectations, and
/// these only say whether the bytes moved. They are also the contract with the
/// Android port, whose suite exports the same `.chipsong` inputs and must
/// produce these same files. Each `song-X.chipsong` goes to `midi-X.mid`.
///
/// `song-export-edge.chipsong` exists for this: a sustained track carried over
/// a pattern boundary and cut by OFF cells, a muted melodic track, a muted
/// noise track beside audible ones, a custom noise track, patterns of three
/// lengths, repeated sections, an unarranged pattern, and non-ASCII names.
final class MidiGoldenTests: XCTestCase {

    private let inputs = [
        "song-library-neon-ascent.chipsong",
        "song-library-boss-door.chipsong",
        "song-export-edge.chipsong",
    ]

    private func goldenName(for input: String) -> String {
        "midi-" + input.dropFirst("song-".count).replacingOccurrences(of: ".chipsong", with: ".mid")
    }

    /// Through the app's own decoder, so the golden starts from what the app
    /// would make of the file, normalization included.
    private func song(_ input: String) throws -> Song {
        try SongDocument.decode(Data(contentsOf: FixtureFiles.url(input)))
    }

    /// Same switch as `GoldenRenderTests`: the scheme's CHIPTUNE_REGEN_GOLDEN,
    /// or a fixture missing from the checkout.
    private func shouldRegenerate(_ golden: String) -> Bool {
        if ProcessInfo.processInfo.environment["CHIPTUNE_REGEN_GOLDEN"] == "1" { return true }
        let repo = FixtureFiles.repoDirectory.appendingPathComponent(golden)
        return !FileManager.default.fileExists(atPath: repo.path)
    }

    func testEachGoldenIsUnchanged() throws {
        for input in inputs {
            let golden = goldenName(for: input)
            guard !shouldRegenerate(golden) else { continue }
            let expected = try Data(contentsOf: FixtureFiles.url(golden))
            let fresh = MidiExport.data(for: try song(input))
            XCTAssertEqual(fresh.count, expected.count, "\(golden): length moved")
            if let at = zip(fresh, expected).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                XCTFail("""
                    \(golden): first difference at byte \(at). If the change was deliberate, \
                    confirm the MidiExport suites still pass, regenerate via the scheme's \
                    CHIPTUNE_REGEN_GOLDEN, say why in the commit, and update Android to match.
                    """)
            }
        }
    }

    /// What can be said of the edge golden without the writer: its shape
    /// follows from the input file alone. A regenerated golden must still
    /// pass this.
    func testTheEdgeGoldenHasTheShapeItsSongImplies() throws {
        let midi = try MidiBytes(Data(contentsOf: FixtureFiles.url("midi-export-edge.mid")))
        XCTAssertEqual(midi.format, 1)
        XCTAssertEqual(midi.division, 96)
        XCTAssertEqual(midi.tracks.count, 7)
        XCTAssertEqual(MidiBytes.name(of: midi.tracks[0]), "Fête Nocturne 夜")
        // 60,000,000 / 150 = 400,000 = 0x061A80.
        XCTAssertEqual(MidiBytes.metas(0x51, in: midi.tracks[0]), [[0x06, 0x1A, 0x80]])
        // A twice, B once, C three times: (2 × 16 + 8 + 3 × 12) × 24.
        let end = (2 * 16 + 8 + 3 * 12) * 24
        for (i, track) in midi.tracks.enumerated() {
            XCTAssertEqual(track.last, MidiBytes.Timed(tick: end, event: .meta(type: 0x2F, bytes: [])), "track \(i)")
        }
        XCTAssertEqual(midi.chipTracks.map { MidiBytes.name(of: $0) },
                       ["Mélodie", "Pulse 2 (muted)", "Triangle", "Noise A", "Noise B (muted)", "Noise C"])
        // The muted pulse has a channel of its own, so it keeps its notes and
        // that channel's volume goes to 0 at the start.
        XCTAssertFalse(MidiBytes.notes(in: midi.tracks[2]).isEmpty)
        XCTAssertEqual(midi.tracks[2].filter { if case .control = $0.event { return true }; return false },
                       [MidiBytes.Timed(tick: 0, event: .control(channel: 1, controller: 7, value: 0))])
        // The muted noise track shares the drum channel with audible ones, so
        // it is left with nothing but its name.
        XCTAssertEqual(midi.tracks[5], [
            MidiBytes.Timed(tick: 0, event: .meta(type: 0x03, bytes: Array("Noise B (muted)".utf8))),
            MidiBytes.Timed(tick: end, event: .meta(type: 0x2F, bytes: [])),
        ])
    }

    // MARK: Regeneration

    /// Normally skipped. Writes into the checkout, not the test bundle, which
    /// is thrown away with the build.
    func testRegenerateGoldens() throws {
        let stale = inputs.filter { shouldRegenerate(goldenName(for: $0)) }
        guard !stale.isEmpty else {
            throw XCTSkip("the MIDI goldens are present; tick CHIPTUNE_REGEN_GOLDEN on the scheme to rewrite them")
        }
        for input in stale {
            let destination = FixtureFiles.repoDirectory.appendingPathComponent(goldenName(for: input))
            try MidiExport.data(for: try song(input)).write(to: destination, options: .atomic)
            print("Wrote MIDI golden to \(destination.path)")
        }
    }
}
