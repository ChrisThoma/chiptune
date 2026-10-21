import XCTest
@testable import Chiptune

/// The video render must never park its thread waiting on AVFoundation work
/// queued at a lower QoS. It runs at user-initiated priority (an export the
/// user is watching), and a semaphore wait on a completion handler that
/// AVFoundation calls back at default QoS is a priority inversion: the
/// waiting thread can't lend its priority to the work it waits for.
///
/// Xcode's Thread Performance Checker, on in test runs, says so on standard
/// error. Off the test's own thread it doesn't reach the test as an issue,
/// so the report is read from standard error itself.
final class VideoExportPriorityTests: XCTestCase {

    /// Everything written to standard error while `body` runs.
    private func standardError(during body: () async throws -> Void) async rethrows -> String {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        let saved = dup(STDERR_FILENO)
        let file = open(log.path, O_WRONLY)
        dup2(file, STDERR_FILENO)
        close(file)
        do {
            try await body()
        } catch {
            fflush(stderr)
            dup2(saved, STDERR_FILENO)
            close(saved)
            throw error
        }
        fflush(stderr)
        dup2(saved, STDERR_FILENO)
        close(saved)
        return (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    }

    func testAVideoRenderWaitsOnNothingAtALowerPriority() async throws {
        var song = TestSongs.empty(name: "Priority", tempo: 240, length: 8)
        song.patterns[0].rows[0][0] = 60
        var options = ExportOptions()
        options.format = .video
        var result: ExportResult?
        let report = await standardError {
            result = await Task.detached(priority: .userInitiated) {
                await VideoExport.render(ExportRequest(song: song, options: options))
            }.value
        }
        guard case .success = result else { return XCTFail("video export did not succeed: \(String(describing: result))") }
        XCTAssertFalse(report.contains("priority inversion"), report)
    }

    /// The labels of the queues the frames were drawn on.
    private final class Queues: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: Set<String> = []
        func record() {
            let label = String(cString: __dispatch_queue_get_label(nil))
            lock.withLock { _ = seen.insert(label) }
        }
        var labels: Set<String> { lock.withLock { seen } }
    }

    /// The draw-and-encode loop runs for the whole render, sleeping whenever
    /// the encoders are busy. On one of Swift concurrency's pool threads it
    /// held that thread the whole time, out of a pool sized to the cores, so
    /// it runs on its own queue and the async render only awaits it.
    func testTheEncodeLoopRunsOffTheConcurrencyPool() async throws {
        var song = TestSongs.empty(name: "Pool", tempo: 240, length: 8)
        song.patterns[0].rows[0][0] = 60
        var options = ExportOptions()
        options.format = .video
        let queues = Queues()
        let result = await Task.detached(priority: .userInitiated) {
            await VideoExport.render(ExportRequest(song: song, options: options),
                                     hooks: VideoExport.Hooks(draw: { _, _ in queues.record() }))
        }.value
        guard case .success = result else { return XCTFail("video export did not succeed: \(result)") }
        let labels = queues.labels
        XCTAssertFalse(labels.isEmpty, "no frame was drawn")
        XCTAssertFalse(labels.contains { $0.contains("cooperative") },
                       "frames were drawn on a concurrency pool thread: \(labels)")
        XCTAssertFalse(labels.contains("com.apple.main-thread"), "frames were drawn on the main thread")
    }
}
