import XCTest
@testable import Chiptune

/// An imported name is untrusted: a blank one must not produce a song the
/// library cannot show, and rename refuses blank names, so neither may import.
final class ImportedSongNameTests: XCTestCase {

    private func importedName(_ name: String) throws -> String {
        var song = Song(name: "Placeholder")
        song.name = name
        let data = try JSONEncoder().encode(song)
        return try SongDocument.decode(data).name
    }

    func testWhitespaceOnlyNameFallsBackToUntitled() throws {
        XCTAssertEqual(try importedName("   "), "Untitled")
    }

    func testEmptyNameFallsBackToUntitled() throws {
        XCTAssertEqual(try importedName(""), "Untitled")
    }

    func testPaddedNameIsTrimmedAndKeepsInternalSpacing() throws {
        XCTAssertEqual(try importedName("  Boss  Door  "), "Boss  Door")
    }

    func testNormalNameIsUnchanged() throws {
        XCTAssertEqual(try importedName("Boss Door"), "Boss Door")
    }

    func testBlankNameStoredInTheLibraryIsNormalizedOnLoad() throws {
        let temp = makeTempStore()
        var song = Song(name: "x")
        song.name = "   "
        temp.save(song)
        XCTAssertEqual(temp.store.load(id: song.id)?.name, "Untitled")
    }
}
