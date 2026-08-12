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
        var song = Song(name: name)
        song.tempo = 240
        song.patterns[0].length = 4
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
        let tail = Int(sampleRate)

        for count in [1, 3] {
            let url = try render(song, ExportOptions(loopCount: count, tailMode: .ringOut))
            XCTAssertEqual(try samples(url).count, pass * count + tail)
        }
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
}

/// Studio's side of export options: progress published, cancel plumbed
/// through, and a cancelled export not raising an error.
@MainActor
final class StudioExportOptionsTests: XCTestCase {

    private func waitUntilIdle(_ studio: Studio, timeout: TimeInterval = 30) {
        let done = expectation(description: "export finishes")
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
            Task { @MainActor in
                if !studio.isExporting { done.fulfill() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }

    func testCancelledExportPublishesNoUrlAndNoError() {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { _ in .cancelled })
        addTeardownBlock { @MainActor in studio.invalidateTimers() }

        studio.export()
        waitUntilIdle(studio)

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
        waitUntilIdle(studio)

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
        waitUntilIdle(studio)

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
        waitUntilIdle(studio)

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
