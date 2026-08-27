import XCTest
import AVFoundation
@testable import Chiptune

/// Export contract, verified from the outside: the file must be a spec-valid
/// 44.1 kHz 16-bit mono WAV, exactly one arrangement pass long, with the
/// final notes' ring-out folded over its start so it loops seamlessly.
/// Everything here is read back through AVAudioFile or a generic RIFF walk —
/// never through the writer's own code.
final class WavExportTests: XCTestCase {

    // MARK: Helpers

    /// Seconds one arrangement pass should take: steps × one step's duration,
    /// where a step is a 16th note (4 per beat) at the song's BPM.
    private func expectedDuration(steps: Int, tempo: Double) -> Double {
        Double(steps) * 60.0 / (tempo * 4.0)
    }

    private func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                   frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0],
                                         count: Int(buf.frameLength)))
    }

    // MARK: Format

    func testExportedFileIsValidWavWithDeclaredFormat() throws {
        var song = TestSongs.empty(tempo: 120)
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[2][8] = 48

        let url = try XCTUnwrap(WavExport.render(song: song))
        let file = try AVAudioFile(forReading: url)

        XCTAssertEqual(file.fileFormat.sampleRate, 44100)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 16)

        // One pass of a 16-step pattern at 120 BPM, 4 steps per beat = 2.0 s.
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertEqual(seconds, expectedDuration(steps: 16, tempo: 120), accuracy: 0.01)
    }

    func testRiffStructureIsInternallyConsistent() throws {
        var song = TestSongs.empty(tempo: 240)
        song.patterns[0].rows[0][0] = 72

        let url = try XCTUnwrap(WavExport.render(song: song))
        let data = try Data(contentsOf: url)

        // Generic RIFF walk, straight from the WAV spec: the RIFF size field
        // covers everything after itself, and every chunk's declared size must
        // land inside the file. The data chunk's payload must run to EOF.
        XCTAssertGreaterThan(data.count, 12)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")

        XCTAssertEqual(le32(data, at: 4), data.count - 8, "RIFF size must cover the rest of the file")

        var offset = 12
        var sawFmt = false, sawData = false
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = le32(data, at: offset + 4)
            XCTAssertLessThanOrEqual(offset + 8 + size, data.count,
                                     "chunk '\(id)' overruns the file")
            if id == "fmt " { sawFmt = true }
            if id == "data" {
                sawData = true
                XCTAssertEqual(offset + 8 + size, data.count,
                               "data chunk must run exactly to end of file")
            }
            offset += 8 + size + (size % 2)
        }
        XCTAssertTrue(sawFmt, "missing fmt chunk")
        XCTAssertTrue(sawData, "missing data chunk")
    }

    // MARK: Loop semantics

    func testFinalNoteRingsIntoTheStartAndFileEndsHot() throws {
        // 16 steps at 120 BPM = 2 s. The only note starts on the last step
        // (1.875 s) and decays for 2 s, so its tail is 3.0 s
        // (`WavExport.tailSeconds`) — longer than the 2 s pass itself, so the
        // fold wraps the *whole* head buffer rather than just its first
        // second. Its ring-out must be audible at the end AND folded over the
        // start, and now also over the previously-untouched middle.
        var song = TestSongs.empty(tempo: 120)
        song.tracks[0].instrument.decay = 2.0
        song.tracks[0].instrument.volume = 0.8
        song.patterns[0].rows[0][15] = 72

        let url = try XCTUnwrap(WavExport.render(song: song))
        let samples = try readSamples(url)
        let sr = 44100

        XCTAssertFalse(samples.contains { $0.isNaN }, "export contains NaN samples")

        let start = RenderHarness.rms(samples[0..<(sr / 10)])
        let middle = RenderHarness.rms(samples[(sr + sr / 5)..<(sr + sr / 2)])   // 1.2–1.5 s
        let end = RenderHarness.rms(samples[(samples.count - sr / 10)...])

        XCTAssertGreaterThan(end, 0.001,
                             "the last note should still be ringing when the file ends — trailing silence breaks the loop")
        XCTAssertGreaterThan(start, 0.001,
                             "the ring-out past the end should be folded over the file's start")
        XCTAssertGreaterThan(middle, 0.001,
                             "with a 3.0s tail wrapping a 2.0s head, even the stretch with no notes of its own now rings from the folded decay")
    }

    /// The tail no longer stops at a flat 1s: a decay of 2.0 needs 3.0s to
    /// reach silence, and the fold must reach that far. A song long enough
    /// that its head buffer isn't wrapped (`bodySamples >= tail`) keeps the
    /// fold a direct, unambiguous overlay — the exported file's audio 1.2s
    /// into the tail must come from decay that a 1s tail would never render.
    func testSeamlessFoldReachesPastTheOldOneSecondBoundary() throws {
        var song = TestSongs.empty(tempo: 120, length: 64)
        song.tracks[0].instrument.decay = 2.0
        song.tracks[0].instrument.volume = 0.9
        song.patterns[0].rows[0][63] = 72   // rings out only at the very end of an 8s pass

        let url = try XCTUnwrap(WavExport.render(song: song))
        let samples = try readSamples(url)
        let sr = 44100

        // 1.2s into the fold (well inside the new 3.0s tail, entirely outside
        // where an old 1.0s tail could ever have reached), the head buffer is
        // otherwise silent song audio, so any energy here can only be the
        // folded decay.
        let window = RenderHarness.rms(samples[(sr + sr / 5)..<(sr + 2 * sr / 5)])   // 1.2–1.4s
        XCTAssertGreaterThan(window, 0.001,
                             "a tail scaled to the decay should still be audibly ringing 1.2s in, past where a flat 1s tail would have already ended")
    }

    func testSongShorterThanRingOutStillExports() throws {
        // 4 steps at 300 BPM = 0.2 s — far shorter than a note's ring-out.
        var song = TestSongs.empty(tempo: 300)
        song.patterns[0].length = 4
        song.tracks[0].instrument.decay = 2.0
        song.patterns[0].rows[0][3] = 72

        let url = try XCTUnwrap(WavExport.render(song: song))
        let samples = try readSamples(url)

        XCTAssertEqual(Double(samples.count) / 44100.0,
                       expectedDuration(steps: 4, tempo: 300), accuracy: 0.01)
        XCTAssertFalse(samples.contains { $0.isNaN }, "export contains NaN samples")
        XCTAssertGreaterThan(RenderHarness.rms(samples[...]), 0.001,
                             "the wrapped ring-out should leave audible content")
        XCTAssertLessThanOrEqual(samples.map { abs($0) }.max() ?? 0, 1.0,
                                 "folded overlap must not exceed full scale")
    }

    // MARK: Filenames

    func testSameNamedSongsDoNotOverwriteEachOther() throws {
        // Same display name, different songs: one silent, one loud. If the
        // second export clobbered the first, re-reading the first would
        // suddenly have the second's audio in it.
        let silent = TestSongs.empty(name: "Twin", tempo: 240)
        var loud = TestSongs.empty(name: "Twin", tempo: 240)
        loud.tracks[0].instrument.sustain = true
        loud.patterns[0].rows[0][0] = 72

        let silentURL = try XCTUnwrap(WavExport.render(song: silent))
        let loudURL = try XCTUnwrap(WavExport.render(song: loud))

        XCTAssertNotEqual(silentURL, loudURL,
                          "two songs with the same name must not share an export path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: silentURL.path))

        XCTAssertLessThan(RenderHarness.rms(try readSamples(silentURL)[...]), 0.0005,
                          "the silent song's export was overwritten with other audio")
        XCTAssertGreaterThan(RenderHarness.rms(try readSamples(loudURL)[...]), 0.001)
    }

    // MARK: Pruning

    func testRenamingASongReplacesItsOldExportRatherThanAccumulating() throws {
        var song = TestSongs.empty(name: "One", tempo: 240)
        song.tracks[0].instrument.sustain = true
        song.patterns[0].rows[0][0] = 60

        let firstURL = try XCTUnwrap(WavExport.render(song: song))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        song.name = "Two"
        let secondURL = try XCTUnwrap(WavExport.render(song: song))

        let dir = firstURL.deletingLastPathComponent()
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".wav") }
        XCTAssertEqual(Set(contents), ["Two.wav"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path),
                       "the stale export should have been pruned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testFailedRerenderPreservesThePreviousExport() throws {
        var song = TestSongs.empty(name: "One", tempo: 240)
        song.tracks[0].instrument.sustain = true
        song.patterns[0].rows[0][0] = 60

        let firstURL = try XCTUnwrap(WavExport.render(song: song))
        let firstBytes = try Data(contentsOf: firstURL)

        song.name = "Two"
        song.tempo = Chip.tempoRange.lowerBound
        song.patterns[0].length = Chip.maxSteps
        song.arrangement = (0..<8).map { _ in
            SongSection(patternID: song.patterns[0].id, repeats: SongSection.maxRepeats)
        }
        let secondResult = WavExport.render(ExportRequest(
            song: song, options: ExportOptions(loopCount: ExportOptions.maxLoopCount)))
        guard case .tooLong = secondResult else {
            return XCTFail("expected the second render to fail, got \(secondResult)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path),
                      "a failed rerender must not touch the previous export")
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
    }
}
