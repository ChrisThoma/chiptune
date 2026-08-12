import XCTest
@testable import Chiptune

/// Calling a track what it is in the song.
///
/// "PU1 / PU2 / TRI / NOI" is standard tracker vocabulary but says nothing
/// about the part — and a song can hold three pulses, at which point the codes
/// are actively unhelpful. A name overrides them wherever a label is shown.
final class TrackNameTests: XCTestCase {

    private func song(kinds: [ChannelKind]) -> Song {
        var song = Song(name: "Named")
        song.tracks = kinds.map { Track(kind: $0) }
        song.patterns[0].rows = kinds.map { _ in Pattern.emptyRow }
        return song
    }

    // MARK: Labels

    func testLabelPrefersTheCustomName() {
        var s = song(kinds: [.triangle])
        s.tracks[0].name = "Bass"

        XCTAssertEqual(s.label(for: 0), "Bass")
        XCTAssertEqual(s.fullLabel(for: 0), "Bass")
    }

    func testAnUnnamedTrackStillReadsAsItsChannel() {
        let s = song(kinds: [.triangle])

        XCTAssertEqual(s.label(for: 0), "TRI")
        XCTAssertEqual(s.fullLabel(for: 0), "Triangle")
    }

    /// A name of nothing but spaces is not a name. Falling through to the
    /// channel beats drawing an empty column header.
    func testABlankNameFallsBackToTheChannel() {
        for blank in ["", "   ", "\t\n"] {
            var s = song(kinds: [.noise])
            s.tracks[0].name = blank
            XCTAssertEqual(s.label(for: 0), "NOI", "blank name \"\(blank)\" was used as a label")
        }
    }

    /// The suffix is derived from position among the same kind, so renaming one
    /// track doesn't shuffle the letter on its neighbour.
    func testDuplicateSuffixesStillApplyToUnnamedTracks() {
        var s = song(kinds: [.triangle, .triangle])
        XCTAssertEqual(s.label(for: 0), "TRI A")
        XCTAssertEqual(s.label(for: 1), "TRI B")

        s.tracks[0].name = "Bass"

        XCTAssertEqual(s.label(for: 0), "Bass")
        XCTAssertEqual(s.label(for: 1), "TRI B", "renaming a sibling moved this track's letter")
    }

    func testNamingBothTracksDropsTheSuffixEntirely() {
        var s = song(kinds: [.pulse1, .pulse1])
        s.tracks[0].name = "Lead"
        s.tracks[1].name = "Harmony"

        XCTAssertEqual(s.label(for: 0), "Lead")
        XCTAssertEqual(s.label(for: 1), "Harmony")
    }

    func testAnOutOfRangeTrackHasNoLabel() {
        let s = song(kinds: [.pulse1])
        XCTAssertEqual(s.label(for: 4), "")
        XCTAssertEqual(s.fullLabel(for: -1), "")
    }

    // MARK: Sanitising

    /// Names come out of `.chipsong` files, which are arbitrary JSON. A long
    /// one would push every grid column off screen.
    func testNormalizeTrimsAndCapsAName() {
        var s = song(kinds: [.pulse1, .pulse2])
        s.tracks[0].name = "  Lead  "
        s.tracks[1].name = String(repeating: "x", count: 500)
        s.normalize()

        XCTAssertEqual(s.tracks[0].name, "Lead")
        XCTAssertLessThanOrEqual(s.tracks[1].name?.count ?? 0, Track.maxNameLength)
    }

    /// A name that is only whitespace normalises away rather than being kept
    /// as a value the label layer has to keep re-checking.
    func testNormalizeDropsABlankName() {
        var s = song(kinds: [.pulse1])
        s.tracks[0].name = "   "
        s.normalize()

        XCTAssertNil(s.tracks[0].name)
    }

    // MARK: Files

    func testANameSurvivesARoundTrip() throws {
        var s = song(kinds: [.triangle, .noise])
        s.tracks[0].name = "Bass"
        s.normalize()

        let restored = try SongDocument.read(contentsOf: try SongDocument.write(s))

        XCTAssertEqual(restored.tracks[0].name, "Bass")
        XCTAssertNil(restored.tracks[1].name, "an unnamed track should stay unnamed")
    }

    /// Songs saved before tracks could be named must still open, and must not
    /// come back carrying an empty name.
    func testAFileWithNoTrackNameStillLoads() throws {
        let old = """
        { "name": "Unnamed tracks", "tempo": 120, "tracks": [
            { "kind": 2, "instrument": { "duty": 2, "volume": 0.9, "decay": 0.35,
                                         "sustain": false, "arpeggio": [] } } ],
          "patterns": [ { "id": "\(UUID().uuidString)", "name": "A", "length": 16,
                          "rows": [[60]] } ],
          "arrangement": [] }
        """

        let song = try SongDocument.decode(Data(old.utf8))

        XCTAssertNil(song.tracks[0].name)
        XCTAssertEqual(song.label(for: 0), "TRI")
    }

    func testAnUnnamedTrackIsNotWrittenIntoTheFile() throws {
        var s = song(kinds: [.pulse1])
        s.normalize()

        let json = try String(contentsOf: try SongDocument.write(s), encoding: .utf8)

        // The song's own name is in there; the track's absence is what matters.
        XCTAssertFalse(json.contains("\"name\" : \"\"") || json.contains("\"name\":\"\""),
                       "an unnamed track should be absent from the file, not present and empty")
    }
}
