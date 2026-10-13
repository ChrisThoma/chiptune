import XCTest
@testable import Chiptune

/// The file's frame: the MThd chunk and the conductor track. Expected bytes
/// are written out from the SMF spec, not read back from the writer.
final class MidiExportHeaderTests: XCTestCase {

    private func parse(_ song: Song) throws -> MidiBytes {
        try MidiBytes(MidiExport.data(for: song))
    }

    // MARK: MThd

    func testHeaderIsFormatOneAtNinetySixTicksPerQuarter() {
        // Four tracks by default, so five chunks with the conductor.
        let data = MidiExport.data(for: TestSongs.empty())
        XCTAssertEqual([UInt8](data.prefix(14)), [
            0x4D, 0x54, 0x68, 0x64,  // "MThd"
            0x00, 0x00, 0x00, 0x06,  // header length
            0x00, 0x01,              // format 1
            0x00, 0x05,              // tracks
            0x00, 0x60,              // 96 ticks per quarter
        ])
    }

    func testTrackCountIsOnePerChipTrackPlusTheConductor() throws {
        for count in [1, 3, Chip.maxTracks] {
            var song = TestSongs.empty()
            song.tracks = (0..<count).map { Track(kind: ChannelKind.allCases[$0 % 4]) }
            song.patterns[0].rows = Array(repeating: Pattern.emptyRow, count: count)
            let midi = try parse(song)
            XCTAssertEqual(midi.declaredTrackCount, count + 1, "\(count) tracks")
            XCTAssertEqual(midi.tracks.count, count + 1, "\(count) tracks: MTrk chunks in the file")
            XCTAssertEqual(midi.format, 1)
            XCTAssertEqual(midi.division, 96)
        }
    }

    // MARK: Conductor

    /// The whole conductor chunk, byte for byte, for a 16-step song at 120:
    /// 500,000 µs per quarter is 07 A1 20, and the song ends at 16 × 24 = 384
    /// ticks, which is 83 00 as a VLQ.
    func testConductorChunkIsExactlyNameTempoMeterAndEnd() {
        let data = [UInt8](MidiExport.data(for: TestSongs.empty(name: "Test", tempo: 120)))
        let conductor: [UInt8] = [
            0x4D, 0x54, 0x72, 0x6B,                       // "MTrk"
            0x00, 0x00, 0x00, 0x1C,                       // 28 bytes follow
            0x00, 0xFF, 0x03, 0x04, 0x54, 0x65, 0x73, 0x74,  // name "Test"
            0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,     // tempo
            0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08,  // 4/4, 24 clocks, 8 32nds
            0x83, 0x00, 0xFF, 0x2F, 0x00,                 // end of track at 384
        ]
        XCTAssertEqual(Array(data[14..<(14 + conductor.count)]), conductor)
    }

    func testTempoIsRoundedMicrosecondsPerQuarter() throws {
        // 60,000,000 / 132 = 454,545.45… → 454,545 = 0x06EF91.
        // 60,000,000 / 70 = 857,142.86… → 857,143 = 0x0D1437: rounds up, so a
        // truncating writer would be off by one here.
        // 60,000,000 / 40 = 1,500,000 = 0x16E360, the slowest tempo there is.
        let cases: [(Double, [UInt8])] = [
            (132, [0x06, 0xEF, 0x91]),
            (70, [0x0D, 0x14, 0x37]),
            (40, [0x16, 0xE3, 0x60]),
        ]
        for (tempo, expected) in cases {
            let midi = try parse(TestSongs.empty(tempo: tempo))
            XCTAssertEqual(MidiBytes.metas(0x51, in: midi.tracks[0]), [expected], "\(tempo) BPM")
        }
    }

    func testOutOfRangeTempoIsClampedFirst() throws {
        // Normalized like the WAV export: 1000 BPM plays as 300, which is
        // 200,000 µs = 0x030D40.
        var song = TestSongs.empty()
        song.tempo = 1000
        let midi = try parse(song)
        XCTAssertEqual(MidiBytes.metas(0x51, in: midi.tracks[0]), [[0x03, 0x0D, 0x40]])
    }

    // MARK: Text

    func testSongNameIsUTF8WithItsByteLength() throws {
        // "Café 歌": é is two bytes and 歌 three, so nine bytes for six
        // characters. A character count would cut the name short.
        let midi = try parse(TestSongs.empty(name: "Café 歌"))
        let expected: [UInt8] = [0x43, 0x61, 0x66, 0xC3, 0xA9, 0x20, 0xE6, 0xAD, 0x8C]
        XCTAssertEqual(MidiBytes.metas(0x03, in: midi.tracks[0]), [expected])
    }

    func testLongNameGetsAMultiByteLength() {
        // 200 bytes needs two VLQ bytes: 200 = 1×128 + 72 → 81 48.
        let name = String(repeating: "L", count: 200)
        let data = [UInt8](MidiExport.data(for: TestSongs.empty(name: name)))
        // MThd (14) + "MTrk" and its length (8) + delta 0, FF 03.
        XCTAssertEqual(Array(data[22..<27]), [0x00, 0xFF, 0x03, 0x81, 0x48])
        XCTAssertEqual(Array(data[27..<227]), Array(repeating: 0x4C, count: 200))
    }

    func testBlankNameIsNormalizedFirst() throws {
        let midi = try parse(TestSongs.empty(name: "  "))
        XCTAssertEqual(MidiBytes.name(of: midi.tracks[0]), Song.defaultName)
    }
}
