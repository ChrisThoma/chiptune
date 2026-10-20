import XCTest
@testable import Chiptune

/// The options side of the video export: the third format, its style, the
/// ending it forces, and the scratch WAV it renders without touching the
/// user's own.
final class VideoExportOptionsTests: XCTestCase {

    private func song(_ name: String = "Video \(UUID().uuidString.prefix(6))") -> Song {
        var song = TestSongs.empty(name: name, tempo: 240, length: 4)
        song.patterns[0].rows[0][0] = 60
        return song
    }

    // MARK: Format

    func testVideoNamesItsFile() {
        XCTAssertEqual(ExportOptions.Format.video.label, "Video")
        XCTAssertEqual(ExportOptions.Format.video.fileExtension, "mp4")
        XCTAssertEqual(ExportOptions.Format.video.fileNoun, "video")
    }

    func testVideoIsFoundFromItsExtensionInAnyCase() {
        XCTAssertEqual(ExportOptions.Format(fileExtension: "MP4"), .video)
        XCTAssertEqual(ExportOptions.Format(fileExtension: "mp4"), .video)
    }

    func testTheFormatsAreOfferedInPickerOrder() {
        XCTAssertEqual(ExportOptions.Format.allCases, [.wav, .midi, .video])
    }

    // MARK: Style

    func testTheStyleDefaultsToGrid() {
        XCTAssertEqual(ExportOptions().videoStyle, .grid)
    }

    func testClampingKeepsTheStyle() {
        var options = ExportOptions()
        options.videoStyle = .cover
        options.loopCount = 99
        XCTAssertEqual(options.clamped.videoStyle, .cover)
    }

    func testEachStyleHasALabel() {
        XCTAssertEqual(ExportOptions.VideoStyle.allCases, [.grid, .cover])
        XCTAssertEqual(ExportOptions.VideoStyle.grid.label, "Grid")
        XCTAssertEqual(ExportOptions.VideoStyle.cover.label, "Cartridge")
    }

    // MARK: Ending

    func testVideoAlwaysRingsOut() {
        var options = ExportOptions()
        options.format = .video
        options.tailMode = .seamlessLoop
        XCTAssertEqual(options.effectiveTailMode, .ringOut)
    }

    func testOtherFormatsKeepTheChosenEnding() {
        for format in [ExportOptions.Format.wav, .midi] {
            for mode in [ExportOptions.TailMode.seamlessLoop, .ringOut] {
                var options = ExportOptions()
                options.format = format
                options.tailMode = mode
                XCTAssertEqual(options.effectiveTailMode, mode, "\(format) \(mode)")
            }
        }
    }

    /// The WAV under a video carries the ring-out, so the picture has a tail
    /// to end on: a video request renders body plus tail even with Seamless
    /// loop still selected from an earlier WAV export.
    func testAVideoRequestRendersItsAudioWithTheTail() throws {
        let song = song()
        var options = ExportOptions()
        options.format = .video
        options.tailMode = .seamlessLoop
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("tail-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard case .success = WavExport.render(ExportRequest(song: song, options: options), to: scratch) else {
            return XCTFail("render failed")
        }
        let perStep = Chip.samplesPerStep(tempo: song.tempo, sampleRate: WavExport.sampleRate)
        let body = perStep * song.arrangementSteps
        let tail = Int(WavExport.sampleRate * WavExport.tailSeconds(for: song))
        let bytes = try Data(contentsOf: scratch).count
        XCTAssertEqual((bytes - 44) / 2, body + tail)
    }

    // MARK: Destination

    /// The video renders its audio to a scratch file. Writing it to the WAV
    /// export's own path would replace the user's last WAV of the song with
    /// a ring-out copy they never asked for.
    func testRenderingToADestinationLeavesTheUsersWavAlone() throws {
        let song = song()
        guard case .success(let userWav) = WavExport.render(ExportRequest(song: song)) else {
            return XCTFail("user WAV render failed")
        }
        let before = try Data(contentsOf: userWav)

        var options = ExportOptions()
        options.loopCount = 3
        options.tailMode = .ringOut
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("dest-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let result = WavExport.render(ExportRequest(song: song, options: options), to: scratch)
        guard case .success(let url) = result else { return XCTFail("got \(result)") }

        XCTAssertEqual(url, scratch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.path))
        XCTAssertEqual(try Data(contentsOf: userWav), before)
    }

    // MARK: Pruning

    /// A song's WAV, MIDI file and video under its current name are each
    /// worth keeping while another is exported; a video left under an old
    /// name goes like any other stale export.
    func testPruningKeepsEachFormatUnderTheCurrentNameAndDropsAStaleVideo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["New.wav", "New.mid", "New.mp4", "Old.mp4", "notes.txt"] {
            try Data([1]).write(to: dir.appendingPathComponent(name))
        }
        ExportFiles.pruneStale(keeping: dir.appendingPathComponent("New.wav"))
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(left, ["New.mid", "New.mp4", "New.wav", "notes.txt"])
    }
}
