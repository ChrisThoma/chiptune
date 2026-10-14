import XCTest
import AudioToolbox
@testable import Chiptune

/// The exported file on disk: that something other than this app's own
/// reader can open it, where it lands, and what it clears away.
final class MidiExportFileTests: XCTestCase {

    private func render(_ song: Song, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let result = MidiExport.render(ExportRequest(song: song))
        guard case .success(let url) = result else {
            XCTFail("expected a file, got \(result)", file: file, line: line)
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private func fileNames(in dir: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
    }

    // MARK: An independent reader

    /// AudioToolbox's SMF parser, the same one the system uses to import MIDI,
    /// stands in for a DAW.
    func testAudioToolboxReadsTheExportAsTheSong() throws {
        var song = TestSongs.golden()
        song.patterns[0].rows[1] = Pattern.emptyRow
        song.patterns[0].rows[1][0] = 64
        let url = try render(song)

        var sequence: MusicSequence?
        XCTAssertEqual(NewMusicSequence(&sequence), noErr)
        let seq = try XCTUnwrap(sequence)
        defer { DisposeMusicSequence(seq) }
        XCTAssertEqual(MusicSequenceFileLoad(seq, url as CFURL, .midiType, []), noErr)

        // Four chip tracks after the conductor. AudioToolbox moves the
        // conductor's tempo onto its own tempo track but keeps the chunk as
        // track 0, so chip track i is its track i + 1.
        var count: UInt32 = 0
        XCTAssertEqual(MusicSequenceGetTrackCount(seq, &count), noErr)
        XCTAssertEqual(count, 5)
        XCTAssertEqual(try notes(in: seq, track: 0).count, 0)

        var tempoTrack: MusicTrack?
        XCTAssertEqual(MusicSequenceGetTempoTrack(seq, &tempoTrack), noErr)
        let tempos = events(in: try XCTUnwrap(tempoTrack)).compactMap { event -> Double? in
            guard event.type == kMusicEventType_ExtendedTempo, let data = event.data else { return nil }
            return data.assumingMemoryBound(to: ExtendedTempoEvent.self).pointee.bpm
        }
        // 132 BPM is stored as 454,545 µs per quarter, a hair over 132.
        XCTAssertEqual(tempos.count, 1)
        XCTAssertEqual(tempos.first ?? 0, 132, accuracy: 0.001)

        // The golden lead plays eight notes, one every half beat; the
        // harmony track now plays one, at the top.
        let lead = try notes(in: seq, track: 1)
        XCTAssertEqual(lead.map(\.note), [72, 76, 79, 76, 74, 77, 81, 79])
        XCTAssertEqual(lead.map(\.beat), [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5])
        let harmony = try notes(in: seq, track: 2)
        XCTAssertEqual(harmony.map(\.note), [64])
        XCTAssertEqual(harmony.map(\.channel), [1])
        // The drums are on channel 10, every hit the Hat preset's open hat.
        let drums = try notes(in: seq, track: 4)
        XCTAssertEqual(Set(drums.map(\.channel)), [9])
        XCTAssertEqual(Set(drums.map(\.note)), [46])
        XCTAssertEqual(drums.count, 6)
    }

    private struct LoadedNote { var beat: Double; var note: UInt8; var channel: UInt8 }

    private func notes(in seq: MusicSequence, track index: UInt32) throws -> [LoadedNote] {
        var track: MusicTrack?
        XCTAssertEqual(MusicSequenceGetIndTrack(seq, index, &track), noErr)
        return events(in: try XCTUnwrap(track)).compactMap { event in
            guard event.type == kMusicEventType_MIDINoteMessage, let data = event.data else { return nil }
            let message = data.assumingMemoryBound(to: MIDINoteMessage.self).pointee
            return LoadedNote(beat: event.time, note: message.note, channel: message.channel)
        }
    }

    private func events(in track: MusicTrack) -> [(time: MusicTimeStamp, type: MusicEventType, data: UnsafeRawPointer?)] {
        var iterator: MusicEventIterator?
        guard NewMusicEventIterator(track, &iterator) == noErr, let it = iterator else { return [] }
        defer { DisposeMusicEventIterator(it) }
        var out: [(MusicTimeStamp, MusicEventType, UnsafeRawPointer?)] = []
        var has: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(it, &has)
        while has.boolValue {
            var time: MusicTimeStamp = 0
            var type: MusicEventType = 0
            var data: UnsafeRawPointer?
            var size: UInt32 = 0
            MusicEventIteratorGetEventInfo(it, &time, &type, &data, &size)
            out.append((time, type, data))
            MusicEventIteratorNextEvent(it)
            MusicEventIteratorHasCurrentEvent(it, &has)
        }
        return out
    }

    // MARK: Where it goes

    func testTheFileIsTheSongsBytesUnderItsSafeName() throws {
        var song = TestSongs.empty(name: "My Song / v2")
        song.patterns[0].rows[0][0] = 60
        let url = try render(song)
        XCTAssertEqual(url, MidiExport.filename(for: song))
        XCTAssertEqual(url.lastPathComponent, "My Song v2.mid")
        XCTAssertEqual(try Data(contentsOf: url), MidiExport.data(for: song))
    }

    func testTheFileSitsInTheSongsOwnExportFolder() {
        // Beside the song's WAV, and apart from any other song's export of
        // the same name.
        let song = Song(name: "Twin")
        XCTAssertEqual(MidiExport.filename(for: song).deletingLastPathComponent(),
                       WavExport.filename(for: song).deletingLastPathComponent())
        XCTAssertNotEqual(MidiExport.filename(for: song), MidiExport.filename(for: Song(name: "Twin")))
    }

    func testALongNameStillMakesAFileName() {
        for name in [String(repeating: "L", count: 300), String(repeating: "歌", count: 90)] {
            let fileName = MidiExport.filename(for: Song(name: name)).lastPathComponent
            XCTAssertLessThanOrEqual(fileName.utf8.count, 255)
            XCTAssertTrue(fileName.hasSuffix(".mid"))
            XCTAssertGreaterThan(fileName.utf8.count, ".mid".utf8.count)
        }
    }

    // MARK: Pruning

    /// Through the dispatcher, which is where the app's exports prune.
    private func export(_ song: Song, as format: ExportOptions.Format) throws -> URL {
        var options = ExportOptions()
        options.format = format
        guard case .success(let url) = Export.render(ExportRequest(song: song, options: options)) else {
            XCTFail("the \(format) export failed")
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    func testAMidiExportClearsARenamedSongsOldMidiAndNothingElse() throws {
        var song = TestSongs.empty(name: "One", tempo: 240)
        song.patterns[0].rows[0][0] = 60
        let dir = try export(song, as: .midi).deletingLastPathComponent()
        _ = try export(song, as: .wav)
        try Data([0]).write(to: dir.appendingPathComponent("keep.txt"))

        song.name = "Two"
        _ = try export(song, as: .midi)
        XCTAssertEqual(try fileNames(in: dir), ["Two.mid", "One.wav", "keep.txt"])
    }

    func testAWavExportClearsARenamedSongsOldWavAndNothingElse() throws {
        var song = TestSongs.empty(name: "One", tempo: 240)
        song.patterns[0].rows[0][0] = 60
        let dir = try export(song, as: .wav).deletingLastPathComponent()
        _ = try export(song, as: .midi)

        song.name = "Two"
        _ = try export(song, as: .wav)
        XCTAssertEqual(try fileNames(in: dir), ["Two.wav", "One.mid"])
    }

    /// Switching formats is not a stale export: the song's WAV and its MIDI
    /// file are both wanted.
    func testEachFormatLeavesTheOthersFileAlone() throws {
        var song = TestSongs.empty(name: "Both", tempo: 240)
        song.patterns[0].rows[0][0] = 60
        let wav = try export(song, as: .wav)
        let mid = try export(song, as: .midi)
        XCTAssertEqual(try fileNames(in: wav.deletingLastPathComponent()), ["Both.wav", "Both.mid"])
        _ = try export(song, as: .wav)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mid.path))
    }

    // MARK: Failure

    func testAFailedWriteReportsItsErrorAndKeepsThePreviousExport() throws {
        var song = TestSongs.empty(name: "One")
        song.patterns[0].rows[0][0] = 60
        let first = try render(song)
        let firstBytes = try Data(contentsOf: first)
        let dir = first.deletingLastPathComponent()

        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        song.name = "Two"
        let result = MidiExport.render(ExportRequest(song: song))
        guard case .failed(let error) = result else {
            return XCTFail("expected the write to fail, got \(result)")
        }
        XCTAssertEqual((error as? CocoaError)?.code, .fileWriteNoPermission, "\(error)")
        XCTAssertEqual(try Data(contentsOf: first), firstBytes)
    }
}
