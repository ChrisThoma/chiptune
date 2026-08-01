import XCTest
@testable import Chiptune

/// Renaming from the library. The App Store copy promises it, so it has to
/// actually stick — including the case the naive implementation gets wrong,
/// where the renamed song is the one currently open and the next save writes
/// the old name straight back over it.
@MainActor
final class SongRenameTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testRenamingAnotherSongPersistsToTheStore() throws {
        var other = Song(name: "Old name")
        temp.save(other)

        studio.rename(other, to: "New name")

        other = try XCTUnwrap(temp.store.load(id: other.id))
        XCTAssertEqual(other.name, "New name")
    }

    /// The failure mode worth having a test for: renaming the open song via the
    /// store alone leaves `studio.song` holding the old name, and the next
    /// autosave undoes the rename.
    func testRenamingTheOpenSongSurvivesTheNextSave() throws {
        studio.song.name = "Working title"
        studio.saveNow()
        let id = studio.song.id

        studio.rename(studio.song, to: "Final title")
        XCTAssertEqual(studio.song.name, "Final title", "the open song must be renamed in place")

        // Whatever the app does next that writes the song must not resurrect
        // the old name.
        studio.saveNow()
        XCTAssertEqual(try XCTUnwrap(temp.store.load(id: id)).name, "Final title")
    }

    func testEmptyOrWhitespaceNameIsRejected() throws {
        var song = Song(name: "Keep me")
        temp.save(song)

        studio.rename(song, to: "   ")

        song = try XCTUnwrap(temp.store.load(id: song.id))
        XCTAssertEqual(song.name, "Keep me", "a blank rename must leave the name alone")
    }

    func testRenameTrimsSurroundingWhitespace() throws {
        var song = Song(name: "Old")
        temp.save(song)

        studio.rename(song, to: "  Padded  ")

        song = try XCTUnwrap(temp.store.load(id: song.id))
        XCTAssertEqual(song.name, "Padded")
    }

    func testDeleteRemovesTheSongFromTheLibrary() {
        let song = Song(name: "Doomed")
        temp.save(song)
        XCTAssertEqual(temp.store.loadAll().count, 2, "the studio's own song plus this one")

        studio.delete(song)

        XCTAssertNil(temp.store.load(id: song.id))
        XCTAssertFalse(temp.store.loadAll().contains { $0.id == song.id })
    }
}
