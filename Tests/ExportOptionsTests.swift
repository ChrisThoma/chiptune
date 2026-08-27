import XCTest
import AVFoundation
@testable import Chiptune

/// Loop count, tail mode, progress and cancellation.
///
/// Durations are asserted against what the tempo and step count say they
/// should be, not against a recorded number — the point of a repeat count is
/// that the file gets longer by exactly one pass.
final class ExportOptionsTests: XCTestCase {

    private let sampleRate = 44100.0

    /// A short song so the repeat tests stay quick: 4 steps at 240 BPM = 0.25 s
    /// a pass. Sustaining, so there is something to ring out.
    private func makeSong(name: String = "Options") -> Song {
        var song = TestSongs.empty(name: name, tempo: 240, length: 4)
        song.tracks[0].instrument.sustain = true
        song.tracks[0].instrument.volume = 0.9
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[0][2] = 67
        return song
    }

    private func onePassSamples(_ song: Song) -> Int {
        let perStep = Int((sampleRate * 60.0 / (song.tempo * 4.0)).rounded())
        return perStep * song.arrangementSteps
    }

    private func render(_ song: Song, _ options: ExportOptions) throws -> URL {
        let result = WavExport.render(ExportRequest(song: song, options: options))
        guard case .success(let url) = result else {
            XCTFail("export did not succeed: \(result)")
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                         count: Int(buffer.frameLength)))
    }

    // MARK: Length

    func testSeamlessLoopIsExactlyTheRequestedNumberOfPasses() throws {
        let song = makeSong()
        let pass = onePassSamples(song)

        for count in [1, 2, 5] {
            let url = try render(song, ExportOptions(loopCount: count, tailMode: .seamlessLoop))
            XCTAssertEqual(try samples(url).count, pass * count,
                           "\(count) repeats should be exactly \(count) passes long")
        }
    }

    /// Ring-out is the same passes plus a second of decay past the end.
    func testRingOutAddsTheTailToTheEnd() throws {
        let song = makeSong()
        let pass = onePassSamples(song)
        let tail = Int(sampleRate * WavExport.tailSeconds(for: song))

        for count in [1, 3] {
            let url = try render(song, ExportOptions(loopCount: count, tailMode: .ringOut))
            XCTAssertEqual(try samples(url).count, pass * count + tail)
        }
    }

    /// A long decay must not be chopped off — the tail scales to give it room
    /// to actually reach silence, and only silence, no audible chop.
    func testRingOutTailScalesWithDecayAndEndsInTrueSilence() throws {
        var song = TestSongs.empty(name: "LongDecay", tempo: 240, length: 4)
        song.tracks[0].instrument.sustain = false
        song.tracks[0].instrument.decay = 4.0
        song.tracks[0].instrument.volume = 0.9
        song.patterns[0].rows[0][3] = 60

        let pass = onePassSamples(song)
        let url = try render(song, ExportOptions(loopCount: 1, tailMode: .ringOut))
        let audio = try samples(url)

        XCTAssertEqual(audio.count, pass + Int(sampleRate * 6.0),
                       "decay 4.0 should push the tail to its 6s ceiling")

        // Culled to exact zero by 5.33s into the tail (4/3 × 4.0); the last
        // 0.25s of a 6s tail is comfortably past that.
        let lastQuarterSecond = audio[(audio.count - Int(sampleRate * 0.25))...]
        XCTAssertEqual(lastQuarterSecond.max() ?? 999, 0, "expected exact digital silence at the end")
        XCTAssertEqual(lastQuarterSecond.min() ?? 999, 0, "expected exact digital silence at the end")
    }

    /// `WavExport.tailSeconds(for:)` in isolation: the floor, the scaling, and
    /// every predicate exclusion that should fall back to the floor.
    func testTailSecondsFormula() {
        var short = TestSongs.empty(length: 4)
        short.tracks[0].instrument.sustain = false
        short.tracks[0].instrument.decay = 0.2
        short.patterns[0].rows[0][0] = 60
        XCTAssertEqual(WavExport.tailSeconds(for: short), 1.0, "short decays keep the 1s floor")

        var scaling = TestSongs.empty(length: 4)
        scaling.tracks[0].instrument.sustain = false
        scaling.tracks[0].instrument.decay = 2.0
        scaling.patterns[0].rows[0][0] = 60
        XCTAssertEqual(WavExport.tailSeconds(for: scaling), 3.0, "decay 2.0 -> tail 3.0")

        var sustaining = TestSongs.empty(length: 4)
        sustaining.tracks[0].instrument.sustain = true
        sustaining.tracks[0].instrument.decay = 4.0
        sustaining.patterns[0].rows[0][0] = 60
        XCTAssertEqual(WavExport.tailSeconds(for: sustaining), 1.0, "a sustaining track releases fast, not counted")

        var muted = TestSongs.empty(length: 4)
        muted.tracks[0].instrument.sustain = false
        muted.tracks[0].instrument.decay = 4.0
        muted.tracks[0].muted = true
        muted.patterns[0].rows[0][0] = 60
        XCTAssertEqual(WavExport.tailSeconds(for: muted), 1.0, "a muted track can't be heard ringing out")

        // Long decay whose only content is a note in a pattern the chain
        // never reaches.
        var orphanPattern = TestSongs.empty(length: 4)
        orphanPattern.tracks[0].instrument.sustain = false
        orphanPattern.tracks[0].instrument.decay = 4.0
        var unreached = Pattern(name: "B", length: 4, trackCount: orphanPattern.tracks.count)
        unreached.rows[0][0] = 60
        orphanPattern.patterns.append(unreached)
        XCTAssertEqual(WavExport.tailSeconds(for: orphanPattern), 1.0,
                       "a note in a pattern outside the chain is never heard")

        // Long decay whose only note is past the pattern's playable length.
        var beyondLength = TestSongs.empty(length: 4)
        beyondLength.tracks[0].instrument.sustain = false
        beyondLength.tracks[0].instrument.decay = 4.0
        beyondLength.patterns[0].length = 2
        beyondLength.patterns[0].rows[0][3] = 60
        XCTAssertEqual(WavExport.tailSeconds(for: beyondLength), 1.0,
                       "a note past the pattern's playable length is never reached")

        // Long decay whose only cell is a note-off.
        var onlyNoteOff = TestSongs.empty(length: 4)
        onlyNoteOff.tracks[0].instrument.sustain = false
        onlyNoteOff.tracks[0].instrument.decay = 4.0
        onlyNoteOff.patterns[0].rows[0][0] = Chip.noteOff
        XCTAssertEqual(WavExport.tailSeconds(for: onlyNoteOff), 1.0,
                       "a note-off makes no sound to ring out")
    }

    func testDefaultOptionsMatchTheOldBehaviour() throws {
        let song = makeSong()
        let plain = try XCTUnwrap(WavExport.render(song: song))
        let explicit = try render(song, ExportOptions())

        XCTAssertEqual(try samples(plain).count, onePassSamples(song))
        XCTAssertEqual(try samples(plain), try samples(explicit),
                       "the simple entry point must still produce the same file")
    }

    func testLoopCountIsClamped() throws {
        let song = makeSong()
        let pass = onePassSamples(song)

        XCTAssertEqual(try samples(try render(song, ExportOptions(loopCount: 0))).count, pass,
                       "zero repeats still has to produce a file")
        XCTAssertEqual(try samples(try render(song, ExportOptions(loopCount: -5))).count, pass)
        XCTAssertEqual(try samples(try render(song, ExportOptions(loopCount: 9999))).count,
                       pass * ExportOptions.maxLoopCount)
    }

    // MARK: Ending

    func testRingOutEndsInSilence() throws {
        let song = makeSong()
        let url = try render(song, ExportOptions(loopCount: 1, tailMode: .ringOut))
        let audio = try samples(url)

        let last = RenderHarness.rms(audio[(audio.count - 4410)...])
        XCTAssertLessThan(last, 0.001, "a ring-out file must finish on silence")

        // And the start must be clean — nothing folded over it.
        let first = RenderHarness.rms(audio[0..<2205])
        XCTAssertGreaterThan(first, 0.001, "the song itself should start straight away")
    }

    /// The seamless loop's whole purpose: it ends hot, because its last notes
    /// are still ringing, and that ring-out is folded over its own start.
    func testSeamlessLoopEndsHot() throws {
        var song = makeSong()
        song.tracks[0].instrument.decay = 2.0
        song.patterns[0].rows[0][0] = Chip.emptyNote
        song.patterns[0].rows[0][2] = Chip.emptyNote
        song.patterns[0].rows[0][3] = 72

        let url = try render(song, ExportOptions(loopCount: 1, tailMode: .seamlessLoop))
        let audio = try samples(url)

        XCTAssertGreaterThan(RenderHarness.rms(audio[(audio.count - 2205)...]), 0.001,
                             "trailing silence would break the loop")
        XCTAssertGreaterThan(RenderHarness.rms(audio[0..<2205]), 0.001,
                             "the ring-out past the end should be folded over the start")
    }

    func testRepeatedPassesActuallyRepeatTheMusic() throws {
        let song = makeSong()
        let pass = onePassSamples(song)
        let audio = try samples(try render(song, ExportOptions(loopCount: 3, tailMode: .ringOut)))

        // Every pass must carry audio — a repeat count that rendered silence
        // after the first pass would still have the right length.
        for index in 0..<3 {
            let window = audio[(index * pass)..<((index + 1) * pass)]
            XCTAssertGreaterThan(RenderHarness.rms(window), 0.001,
                                 "pass \(index) is silent")
        }
    }

    func testNoOptionCombinationProducesNaNOrClipping() throws {
        let song = makeSong()
        for count in [1, 2] {
            for mode in [ExportOptions.TailMode.seamlessLoop, .ringOut] {
                let audio = try samples(try render(song, ExportOptions(loopCount: count,
                                                                      tailMode: mode)))
                XCTAssertFalse(audio.contains { !$0.isFinite }, "\(count)×, \(mode)")
                XCTAssertLessThanOrEqual(RenderHarness.peak(audio), 1.0, "\(count)×, \(mode)")
            }
        }
    }

    // MARK: Progress

    func testProgressIsMonotonicWithinZeroToOneAndReachesTheEnd() throws {
        let song = makeSong()
        let reported = Locked<[Double]>([])

        let result = WavExport.render(ExportRequest(
            song: song,
            options: ExportOptions(loopCount: 3, tailMode: .ringOut),
            progress: { fraction in reported.mutate { $0.append(fraction) } }))

        guard case .success = result else { return XCTFail("export failed") }

        let values = reported.value
        XCTAssertFalse(values.isEmpty, "a multi-second render reported no progress at all")
        for fraction in values {
            XCTAssertTrue((0...1).contains(fraction), "progress out of range: \(fraction)")
        }
        XCTAssertEqual(values, values.sorted(), "progress went backwards")
        XCTAssertEqual(values.last ?? 0, 1.0, accuracy: 0.001,
                       "progress must finish at 100%, not stall short of it")
    }

    // MARK: Cancellation

    /// Cancelling is not failing, and it must not leave a half-written file
    /// behind — one would show up in the share sheet and play as noise.
    func testCancellingLeavesNoFileAndReportsCancelledRatherThanFailed() throws {
        var song = makeSong(name: "Cancelled")
        // Long enough that the cancel lands mid-render rather than after it.
        song.tempo = 40
        song.patterns[0].length = 64
        song.arrangement[0].repeats = 8

        let calls = Locked<Int>(0)
        let result = WavExport.render(ExportRequest(
            song: song,
            options: ExportOptions(loopCount: 4, tailMode: .ringOut),
            isCancelled: {
                // Let a few chunks through, then pull the plug.
                calls.mutate { $0 += 1 }
                return calls.value > 3
            }))

        guard case .cancelled = result else {
            return XCTFail("expected .cancelled, got \(result)")
        }

        // No output file for this song, and no raw scratch files left over.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(song.id.uuidString, isDirectory: true)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "a cancelled export left files behind: \(leftovers)")
    }

    func testCancellingBeforeTheFirstChunkStillCancelsCleanly() {
        let result = WavExport.render(ExportRequest(song: makeSong(),
                                                    isCancelled: { true }))
        guard case .cancelled = result else {
            return XCTFail("expected .cancelled, got \(result)")
        }
    }

    func testAnUncancelledExportIsNotReportedAsCancelled() throws {
        let result = WavExport.render(ExportRequest(song: makeSong(),
                                                    isCancelled: { false }))
        guard case .success = result else {
            return XCTFail("expected .success, got \(result)")
        }
    }

    func testAnOversizedWavIsRejectedBeforeRendering() {
        var song = Song(name: "Too Long")
        song.tempo = Chip.tempoRange.lowerBound
        song.patterns[0].length = Chip.maxSteps
        song.arrangement = (0..<8).map { _ in
            SongSection(patternID: song.patterns[0].id,
                        repeats: SongSection.maxRepeats)
        }
        let options = ExportOptions(loopCount: ExportOptions.maxLoopCount)
        let started = Date()

        let result = WavExport.render(ExportRequest(song: song, options: options))

        guard case .tooLong = result else {
            return XCTFail("expected .tooLong, got \(result)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1,
                          "size validation happened after rendering began")
    }
}

/// Studio's side of export options: progress published, cancel plumbed
/// through, and a cancelled export not raising an error.
@MainActor
final class StudioExportOptionsTests: XCTestCase {

    func testEvenImmediateCompletionsPublishDistinctAttemptTokens() {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { _ in .failed })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        let first = studio.export()
        waitForExport(studio)
        XCTAssertEqual(studio.completedExportAttempt, first)

        studio.renderer = { _ in .cancelled }
        let second = studio.export()
        waitForExport(studio)
        XCTAssertEqual(studio.completedExportAttempt, second)
        XCTAssertNotEqual(first, second)
    }

    /// Spins the run loop briefly so a `Task { @MainActor in ... }` enqueued
    /// just before this call gets a turn before the assertions run.
    private func flushMainActor() {
        let exp = expectation(description: "main actor flush")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    func testProgressArrivingAfterFinishDoesNotResurrectTheBar() {
        let stashed = Locked<(@Sendable (Double) -> Void)?>(nil)
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { request in
            stashed.mutate { $0 = request.progress }
            return .success(FileManager.default.temporaryDirectory
                .appendingPathComponent("stale-\(UUID().uuidString).wav"))
        })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitForExport(studio)
        XCTAssertEqual(studio.exportProgress, 0)

        stashed.value?(0.7)
        flushMainActor()

        XCTAssertEqual(studio.exportProgress, 0,
                       "a progress update arriving after the export finished must not resurrect the bar")
    }

    func testStaleProgressFromPreviousExportCannotOverwriteActiveExport() {
        let stashedA = Locked<(@Sendable (Double) -> Void)?>(nil)
        let bStarted = expectation(description: "B started")
        let releaseB = Locked<Bool>(false)

        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { request in
            stashedA.mutate { $0 = request.progress }
            return .success(FileManager.default.temporaryDirectory
                .appendingPathComponent("a-\(UUID().uuidString).wav"))
        })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitForExport(studio)

        studio.renderer = { request in
            bStarted.fulfill()
            while !releaseB.value { usleep(1000) }
            request.progress(0.3)
            return .success(FileManager.default.temporaryDirectory
                .appendingPathComponent("b-\(UUID().uuidString).wav"))
        }
        studio.export()
        wait(for: [bStarted], timeout: 10)

        // A's own (stale) progress closure fires while B is mid-flight.
        stashedA.value?(0.9)
        flushMainActor()

        XCTAssertNotEqual(studio.exportProgress, 0.9,
                          "a stale export's progress must not overwrite the active export's bar")

        releaseB.mutate { $0 = true }
        waitForExport(studio)
    }

    func testCancelledExportPublishesNoUrlAndNoError() {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { _ in .cancelled })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitForExport(studio)

        XCTAssertNil(studio.exportURL)
        XCTAssertNil(studio.exportError, "cancelling is not an error")
        XCTAssertEqual(studio.exportProgress, 0)
    }

    /// `cancelExport()` has to reach the render thread, which is polling a
    /// flag the main actor sets.
    func testCancelExportReachesTheRenderer() {
        let started = expectation(description: "renderer started")
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { request in
            started.fulfill()
            // Spin until the main actor cancels, the way the real renderer
            // polls at chunk boundaries.
            while !request.isCancelled() { usleep(1000) }
            return .cancelled
        })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        wait(for: [started], timeout: 10)
        studio.cancelExport()
        waitForExport(studio)

        XCTAssertFalse(studio.isExporting)
        XCTAssertNil(studio.exportError)
    }

    func testProgressReachesTheStudio() {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { request in
            request.progress(0.5)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("progress-\(UUID().uuidString).wav")
            return .success(url)
        })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitForExport(studio)

        XCTAssertNotNil(studio.exportURL)
        // Reset once finished, so a second export doesn't open on a stale bar.
        XCTAssertEqual(studio.exportProgress, 0)
    }

    func testOptionsReachTheRenderer() {
        let seen = Locked<ExportOptions?>(nil)
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { request in
            seen.mutate { $0 = request.options }
            return .success(FileManager.default.temporaryDirectory
                .appendingPathComponent("opts-\(UUID().uuidString).wav"))
        })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export(options: ExportOptions(loopCount: 4, tailMode: .ringOut))
        waitForExport(studio)

        XCTAssertEqual(seen.value, ExportOptions(loopCount: 4, tailMode: .ringOut))
    }
}

/// Shared between the test's thread and the renderer's. A plain captured `var`
/// would be a race in the test rather than in the code under test.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        body(&stored)
        lock.unlock()
    }

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
