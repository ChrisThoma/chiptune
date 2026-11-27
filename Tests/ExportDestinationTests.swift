import XCTest
@testable import Chiptune

/// Where the Mac's save panel opens for an export, and what it offers to
/// call the file. The panel itself can't be driven from a unit test; these
/// are the decisions it is handed.
final class ExportDestinationTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func file(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    /// The export is already named for the song (`ExportFiles.url`), in a
    /// per-song temp folder whose name is a UUID. The panel offers the file's
    /// name, never the folder's.
    func testTheSuggestedNameIsTheSongsFileName() {
        XCTAssertEqual(ExportDestination.suggestedName(for: file("Crystal Cavern.mp4")),
                       "Crystal Cavern.mp4")
        XCTAssertEqual(ExportDestination.suggestedName(for: file("Bonewake.chipsong")),
                       "Bonewake.chipsong")
    }

    /// Each kind of file opens where a Mac keeps that kind: video in Movies,
    /// audio and MIDI in Music, a song file in Documents.
    func testEachFormatOpensInTheFolderForItsKind() {
        XCTAssertEqual(ExportDestination.directory(for: file("a.mp4"), home: home).path,
                       "/Users/someone/Movies")
        XCTAssertEqual(ExportDestination.directory(for: file("a.wav"), home: home).path,
                       "/Users/someone/Music")
        XCTAssertEqual(ExportDestination.directory(for: file("a.mid"), home: home).path,
                       "/Users/someone/Music")
        XCTAssertEqual(ExportDestination.directory(for: file("a.chipsong"), home: home).path,
                       "/Users/someone/Documents")
    }

    func testExtensionsAreMatchedWithoutRegardToCase() {
        XCTAssertEqual(ExportDestination.directory(for: file("a.MP4"), home: home).path,
                       "/Users/someone/Movies")
    }

    func testAnythingElseOpensInDownloads() {
        XCTAssertEqual(ExportDestination.directory(for: file("a.txt"), home: home).path,
                       "/Users/someone/Downloads")
    }

    /// A sandboxed app's home is its container. The panel should open in the
    /// person's real Movies folder, not the container's copy of one.
    func testTheDefaultHomeIsTheUsersRealHomeNotTheContainer() {
        XCTAssertFalse(ExportDestination.userHome.path.contains("/Library/Containers/"),
                       ExportDestination.userHome.path)
    }

    /// The save panel has already asked whether to replace a file of the same
    /// name, so saving over one replaces it rather than failing.
    func testCopyReplacesAFileTheSavePanelAlreadyAgreedToReplace() throws {
        let source = file("song.wav")
        let destination = file("song.wav")
        for url in [source, destination] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)

        try ExportDestination.copy(source, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "The export stays where the share flow can still find it")
    }
}
