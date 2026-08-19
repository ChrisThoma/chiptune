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
        // (1.875 s) and decays for 2 s, so on a seamless loop its ring-out
        // must be audible at the very end of the file AND folded over the
        // start — while the un-folded middle stays silent.
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
        XCTAssertLessThan(middle, 0.0005,
                          "the stretch with no notes and no fold should be silent")
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
}
