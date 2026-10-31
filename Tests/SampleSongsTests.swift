import XCTest
@testable import Chiptune

/// The sample songs that ship in the bundle: seeded alongside First Loop on a
/// first launch, and once into libraries that already exist.
final class SampleSongsTests: XCTestCase {

    private var temp: TempStore!
    /// Where the hand-made sample files for a test are written.
    private var sampleDir: URL!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        sampleDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chiptune-samples-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: sampleDir)
        temp = nil
        super.tearDown()
    }

    private let bundledNames = ["Sky Arcade", "Rainy Waltz", "Tower Climb"]

    private func launch(_ samples: SampleSongs = .bundled) -> Studio {
        Studio(store: temp.store, autosaveEnabled: false, samples: samples)
    }

    /// Writes `song` as a .chipsong file and returns its URL.
    private func sampleFile(_ song: Song) throws -> URL {
        let url = sampleDir.appendingPathComponent("\(song.id.uuidString).chipsong")
        try JSONEncoder().encode(song).write(to: url)
        return url
    }

    private func names() -> [String] { temp.store.loadAll().map(\.name) }

    // MARK: The bundle

    func testTheBundledSamplesDecodeWithTheirNames() throws {
        let songs = SampleSongs.bundled.load()
        XCTAssertEqual(songs.map(\.name), bundledNames)
        XCTAssertEqual(Set(songs.map(\.id)).count, 3, "each sample needs its own id")
        for song in songs {
            XCTAssertFalse(song.patterns.isEmpty, song.name)
            XCTAssertFalse(song.arrangement.isEmpty, song.name)
        }
    }

    // MARK: First launch

    func testFirstLaunchSeedsFirstLoopAndTheSamplesWithFirstLoopOpenAndFirst() {
        let studio = launch()

        XCTAssertEqual(studio.song.name, "First Loop")
        XCTAssertEqual(names(), ["First Loop"] + bundledNames)

        let relaunched = launch()
        XCTAssertEqual(relaunched.song.name, "First Loop", "a relaunch reopens First Loop")
        XCTAssertEqual(names().count, 4, "a relaunch seeds nothing more")
    }

    // MARK: Existing libraries

    func testAnExistingLibraryGetsTheSamplesOnceAndKeepsItsOpenSong() {
        let mine = Song(name: "Mine")
        temp.save(mine, makeCurrent: true)

        let studio = launch()
        XCTAssertEqual(studio.song.id, mine.id)
        XCTAssertEqual(Set(names()), Set(["Mine"] + bundledNames))
        XCTAssertFalse(names().contains("First Loop"), "First Loop is only for an empty library")

        let relaunched = launch()
        XCTAssertEqual(relaunched.song.id, mine.id)
        XCTAssertEqual(names().count, 4)
    }

    /// A library whose open song was only ever found as the newest file (no
    /// remembered current song) must not reopen on a sample next time.
    func testSeedingDoesNotChangeTheSongThatOpensWhenNoneWasRemembered() throws {
        let mine = Song(name: "Mine")
        temp.save(mine, makeCurrent: false)
        let stamped = try XCTUnwrap(temp.store.load(id: mine.id)).modified

        XCTAssertEqual(launch().song.id, mine.id)
        XCTAssertEqual(temp.defaults.string(forKey: "currentSongID"), mine.id.uuidString,
                       "the reopened song is remembered once samples are seeded")
        XCTAssertEqual(try XCTUnwrap(temp.store.load(id: mine.id)).modified, stamped,
                       "remembering it writes only the key, never the song")
        XCTAssertEqual(launch().song.id, mine.id)
    }

    func testSeededSamplesAreRecordedAsUppercaseIDs() throws {
        _ = launch()
        let recorded = try XCTUnwrap(temp.defaults.stringArray(forKey: "seededSampleSongIDs"))
        let ids = SampleSongs.bundled.load().map(\.id.uuidString)
        XCTAssertEqual(Set(recorded), Set(ids))
        XCTAssertEqual(recorded, recorded.map { $0.uppercased() })
    }

    /// An unreadable file holding a sample's id is still the user's file.
    func testAnUnreadableFileWithASampleIDIsLeftAloneAndRecorded() throws {
        let sample = Song(name: "Sample")
        let url = try sampleFile(sample)
        let file = temp.directory.appendingPathComponent("\(sample.id.uuidString).json")
        try Data("damaged".utf8).write(to: file)

        _ = launch(SampleSongs(urls: [url]))

        XCTAssertEqual(try Data(contentsOf: file), Data("damaged".utf8))
        XCTAssertEqual(temp.defaults.stringArray(forKey: "seededSampleSongIDs"), [sample.id.uuidString])
    }

    func testADeletedSampleIsNotSeededAgain() throws {
        _ = launch()
        let sky = try XCTUnwrap(temp.store.loadAll().first { $0.name == "Sky Arcade" })
        try temp.store.delete(sky)

        _ = launch()

        XCTAssertNil(temp.store.load(id: sky.id))
        XCTAssertEqual(names(), ["First Loop", "Rainy Waltz", "Tower Climb"])
    }

    /// A sample added in a later version reaches a library that already had
    /// the earlier ones, without bringing back one the user deleted.
    func testANewSampleIsSeededOnceWithoutBringingBackDeletedOnes() throws {
        let a = Song(name: "A"), b = Song(name: "B"), c = Song(name: "C")
        let urlA = try sampleFile(a), urlB = try sampleFile(b), urlC = try sampleFile(c)

        _ = launch(SampleSongs(urls: [urlA, urlB]))
        try temp.store.delete(a)

        _ = launch(SampleSongs(urls: [urlA, urlB, urlC]))

        XCTAssertEqual(Set(names()), ["First Loop", "B", "C"])
    }

    func testAnExistingFileWithASampleIDIsNotOverwritten() throws {
        let sample = Song(name: "Sample")
        let url = try sampleFile(sample)
        var edited = sample
        edited.name = "My edit"
        temp.save(edited, makeCurrent: true)

        let studio = launch(SampleSongs(urls: [url]))

        XCTAssertEqual(temp.store.load(id: sample.id)?.name, "My edit")
        XCTAssertEqual(studio.song.name, "My edit")
        XCTAssertEqual(names(), ["My edit"])
    }

    func testAMissingOrBrokenSampleIsSkippedQuietly() throws {
        let broken = sampleDir.appendingPathComponent("broken.chipsong")
        try Data("not a song".utf8).write(to: broken)
        let missing = sampleDir.appendingPathComponent("missing.chipsong")
        let good = Song(name: "Good")
        let goodURL = try sampleFile(good)

        let studio = launch(SampleSongs(urls: [broken, missing, goodURL]))

        XCTAssertEqual(names(), ["First Loop", "Good"])
        XCTAssertNil(studio.importError)
        XCTAssertNil(studio.storageError)
        XCTAssertNil(studio.unreadableSongsNotice)
    }

    /// A bundle without the sample files still launches into First Loop.
    func testABundleWithoutTheSamplesSeedsNone() {
        let empty = SampleSongs(bundle: Bundle(for: SampleSongsTests.self))
        XCTAssertTrue(empty.load().isEmpty)

        _ = launch(empty)
        XCTAssertEqual(names(), ["First Loop"])
    }
}
