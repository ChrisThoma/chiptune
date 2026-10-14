import XCTest
@testable import Chiptune

/// A song name has no length cap, but file names do (255 bytes, counting the
/// extension, in UTF-8). Sharing and exporting must truncate the file name
/// rather than fail, and must leave the song's own name alone.
final class LongSongNameFileTests: XCTestCase {

    private func assertFits(_ url: URL, ext: String, file: StaticString = #filePath, line: UInt = #line) {
        let name = url.lastPathComponent
        XCTAssertLessThanOrEqual(name.utf8.count, 255, file: file, line: line)
        XCTAssertTrue(name.hasSuffix(".\(ext)"), file: file, line: line)
        XCTAssertGreaterThan(name.utf8.count, ext.count + 1, file: file, line: line)
    }

    func testSongFileWriteSurvivesA300CharacterName() throws {
        let song = Song(name: String(repeating: "L", count: 300))
        let url = try SongDocument.write(song)
        assertFits(url, ext: SongDocument.fileExtension)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(song.name.count, 300)
    }

    func testSongFileWriteSurvivesAnOverLongCJKName() throws {
        let song = Song(name: String(repeating: "歌", count: 90))
        let url = try SongDocument.write(song)
        assertFits(url, ext: SongDocument.fileExtension)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSongFileNormalNameIsUnchanged() throws {
        let url = try SongDocument.write(Song(name: "My Song"))
        XCTAssertEqual(url.lastPathComponent, "My Song.\(SongDocument.fileExtension)")
    }

    func testWavFilenameSurvivesA300CharacterName() {
        let url = WavExport.filename(for: Song(name: String(repeating: "L", count: 300)))
        assertFits(url, ext: "wav")
    }

    func testWavFilenameSurvivesAnOverLongCJKName() {
        let url = WavExport.filename(for: Song(name: String(repeating: "歌", count: 90)))
        assertFits(url, ext: "wav")
    }

    func testWavFilenameNormalNameIsUnchanged() {
        let url = WavExport.filename(for: Song(name: "My Song"))
        XCTAssertEqual(url.lastPathComponent, "My Song.wav")
    }

    func testMidiFilenameSurvivesA300CharacterName() {
        assertFits(MidiExport.filename(for: Song(name: String(repeating: "L", count: 300))), ext: "mid")
    }

    func testMidiFilenameSurvivesAnOverLongCJKName() {
        assertFits(MidiExport.filename(for: Song(name: String(repeating: "歌", count: 90))), ext: "mid")
    }

    func testMidiFilenameNormalNameIsUnchanged() {
        XCTAssertEqual(MidiExport.filename(for: Song(name: "My Song")).lastPathComponent, "My Song.mid")
    }
}
