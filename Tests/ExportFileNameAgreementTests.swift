import XCTest
@testable import Chiptune

/// One song maps to one safe file base name, whichever export produced it.
final class ExportFileNameAgreementTests: XCTestCase {
    private func bases(_ name: String) throws -> (song: String, wav: String, mid: String) {
        let song = Song(name: name)
        let songURL = try SongDocument.write(song)
        let wavURL = WavExport.filename(for: song)
        let midURL = MidiExport.filename(for: song)
        return (songURL.deletingPathExtension().lastPathComponent,
                wavURL.deletingPathExtension().lastPathComponent,
                midURL.deletingPathExtension().lastPathComponent)
    }

    func testSlashTitleAgrees() throws {
        let b = try bases("My Song / v2")
        XCTAssertEqual(b.song, "My Song v2")
        XCTAssertEqual(b.wav, b.song)
        XCTAssertEqual(b.mid, b.song)
    }

    func testRepeatedSpacesAndDotsAgree() throws {
        let b = try bases("  a..b   c . d  ")
        XCTAssertEqual(b.wav, b.song)
        XCTAssertEqual(b.wav, "ab c d")
        XCTAssertEqual(b.mid, b.song)
    }

    func testEmojiOnlyFallsBackInBoth() throws {
        let b = try bases("🎵🎶")
        XCTAssertEqual(b.song, "chiptune")
        XCTAssertEqual(b.wav, "chiptune")
        XCTAssertEqual(b.mid, "chiptune")
    }

    func testBlankFallsBackInBoth() throws {
        let b = try bases("   ")
        XCTAssertEqual(b.wav, b.song)
        XCTAssertEqual(b.mid, b.song)
        XCTAssertEqual(b.wav, "chiptune")
    }
}
