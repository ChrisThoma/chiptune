import XCTest
@testable import Chiptune

/// The song's musical key: which notes it numbers on the piano, how it is saved
/// (Android writes the same JSON, so the shape is fixed), and that setting it
/// is an ordinary undoable edit.
@MainActor
final class MusicalKeyTests: XCTestCase {

    // MARK: Scale membership

    func testCMajorContainsTheWhiteKeysOnly() {
        let key = MusicalKey(root: 0, scale: .major)
        let inKey = (60..<72).filter(key.contains)
        XCTAssertEqual(inKey, [60, 62, 64, 65, 67, 69, 71])
        XCTAssertTrue(key.isRoot(60))
        XCTAssertTrue(key.isRoot(48))
        XCTAssertFalse(key.isRoot(62))
    }

    func testAMinorSharesCMajorsNotesButNotItsRoot() {
        let key = MusicalKey(root: 9, scale: .minor)
        let inKey = (60..<72).filter(key.contains)
        XCTAssertEqual(inKey, [60, 62, 64, 65, 67, 69, 71])
        XCTAssertTrue(key.isRoot(69))
        XCTAssertFalse(key.isRoot(60))
    }

    func testFSharpMajor() {
        let key = MusicalKey(root: 6, scale: .major)
        // F# G# A# B C# D# E#(F)
        let inKey = (60..<72).filter(key.contains)
        XCTAssertEqual(inKey, [61, 63, 65, 66, 68, 70, 71])
        XCTAssertTrue(key.isRoot(66))
    }

    func testPitchClassHoldsForNegativeAndHighNotes() {
        let key = MusicalKey(root: 6, scale: .major)
        // -6 is pitch class 6 (F#), -1 is 11 (B), -2 is 10 (A#), -5 is 7 (G).
        XCTAssertTrue(key.isRoot(-6))
        XCTAssertTrue(key.contains(-1))
        XCTAssertTrue(key.contains(-2))
        XCTAssertFalse(key.contains(-5))
        XCTAssertTrue(key.isRoot(126))
        XCTAssertFalse(key.contains(127), "127 is G, which F# major does not have")
    }

    // MARK: Piano marks

    func testDegreesInCMajor() {
        let key = MusicalKey(root: 0, scale: .major)
        let degrees = [60, 62, 64, 65, 67, 69, 71].map(key.degree)
        XCTAssertEqual(degrees, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertNil(key.degree(61))
        XCTAssertEqual(key.degree(48), 1)
        XCTAssertEqual(key.degree(-1), 7, "-1 is B")
    }

    func testDegreesInFSharpMinor() {
        let key = MusicalKey(root: 6, scale: .minor)
        // F# G# A B C# D E
        let degrees = [66, 68, 69, 71, 73, 74, 76].map(key.degree)
        XCTAssertEqual(degrees, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertNil(key.degree(67), "G is not in F# minor")
        XCTAssertNil(key.degree(70), "A# is not in F# minor")
    }

    func testDegreeAccessibilityValue() {
        let key = MusicalKey(root: 0, scale: .major)
        XCTAssertEqual(KeyMark.accessibilityValue(key: key, midi: 60), "degree 1, root")
        XCTAssertEqual(KeyMark.accessibilityValue(key: key, midi: 64), "degree 3")
        XCTAssertNil(KeyMark.accessibilityValue(key: key, midi: 61))
        XCTAssertNil(KeyMark.accessibilityValue(key: nil, midi: 60))
    }

    func testKeyButtonText() {
        XCTAssertEqual(KeyMark.buttonLabel(nil), "KEY")
        XCTAssertEqual(KeyMark.buttonLabel(MusicalKey(root: 6, scale: .minor)), "F# min")
        XCTAssertEqual(KeyMark.buttonValue(nil), "none")
        XCTAssertEqual(KeyMark.buttonValue(MusicalKey(root: 0, scale: .major)), "C major")
    }

    // MARK: Labels

    func testLabels() {
        XCTAssertEqual(MusicalKey(root: 0, scale: .major).shortLabel, "C maj")
        XCTAssertEqual(MusicalKey(root: 6, scale: .minor).shortLabel, "F# min")
        XCTAssertEqual(MusicalKey(root: 0, scale: .major).spokenLabel, "C major")
        XCTAssertEqual(MusicalKey(root: 9, scale: .minor).spokenLabel, "A minor")
    }

    // MARK: Saving

    private func json(_ song: Song) throws -> [String: Any] {
        let data = try JSONEncoder().encode(song)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A saved song with its "key" field swapped for `key` (or removed).
    private func decode(withKey key: Any?) throws -> Song {
        var object = try json(Song(name: "Keyed"))
        object["key"] = key
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Song.self, from: data)
    }

    func testKeyRoundTrips() throws {
        var song = Song(name: "Keyed")
        song.key = MusicalKey(root: 6, scale: .minor)
        let data = try JSONEncoder().encode(song)
        let back = try JSONDecoder().decode(Song.self, from: data)
        XCTAssertEqual(back.key, MusicalKey(root: 6, scale: .minor))
    }

    func testKeyIsWrittenInTheSharedShape() throws {
        var song = Song(name: "Keyed")
        song.key = MusicalKey(root: 2, scale: .major)
        let key = try XCTUnwrap(try json(song)["key"] as? [String: Any])
        XCTAssertEqual(key["root"] as? Int, 2)
        XCTAssertEqual(key["scale"] as? String, "major")
        XCTAssertEqual(key.count, 2)
    }

    func testNoKeyOmitsTheField() throws {
        XCTAssertNil(try json(Song(name: "Plain"))["key"])
    }

    func testFileWithoutAKeyDecodesToNone() throws {
        XCTAssertNil(try decode(withKey: nil).key)
    }

    func testBadRootDecodesToNoneWithoutLosingTheSong() throws {
        for root in [-1, 12, 99] {
            let song = try decode(withKey: ["root": root, "scale": "major"])
            XCTAssertNil(song.key, "root \(root)")
            XCTAssertEqual(song.name, "Keyed")
        }
    }

    func testUnknownScaleDecodesToNoneWithoutLosingTheSong() throws {
        let song = try decode(withKey: ["root": 0, "scale": "dorian"])
        XCTAssertNil(song.key)
        XCTAssertEqual(song.name, "Keyed")
    }

    func testMalformedKeyDecodesToNone() throws {
        XCTAssertNil(try decode(withKey: "C major").key)
        XCTAssertNil(try decode(withKey: ["root": "C", "scale": "major"]).key)
    }

    // MARK: Studio

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Key"))
        studio.undoCoalescingWindow = 0
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testSetKeyIsUndoable() {
        XCTAssertNil(studio.song.key)
        studio.setKey(MusicalKey(root: 7, scale: .major))
        XCTAssertEqual(studio.song.key, MusicalKey(root: 7, scale: .major))
        XCTAssertTrue(studio.canUndo)

        studio.setKey(nil)
        XCTAssertNil(studio.song.key)

        studio.undo()
        XCTAssertEqual(studio.song.key, MusicalKey(root: 7, scale: .major))
        studio.undo()
        XCTAssertNil(studio.song.key)
        studio.redo()
        XCTAssertEqual(studio.song.key, MusicalKey(root: 7, scale: .major))
    }

    func testSettingTheSameKeyIsNotAnEdit() {
        studio.setKey(MusicalKey(root: 0, scale: .minor))
        studio.undo()
        XCTAssertTrue(studio.canRedo)
        studio.setKey(nil)
        XCTAssertTrue(studio.canRedo, "choosing the key already set must not wipe Redo")
    }

    func testSetKeyMarksTheSongChanged() {
        let before = studio.song
        studio.setKey(MusicalKey(root: 0, scale: .major))
        XCTAssertNotEqual(studio.song, before)
    }
}
