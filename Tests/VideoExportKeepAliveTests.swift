import XCTest
import AVFoundation
@testable import Chiptune

/// The words for a video render the system stopped because the app left the
/// screen. Retrying in the same way fails the same way; staying in the app
/// is what fixes it.
final class InterruptedExportMessageTests: XCTestCase {
    private let generic = NSError(domain: AVFoundationErrorDomain, code: AVError.unknown.rawValue)
    private let interrupted = NSError(domain: AVFoundationErrorDomain, code: AVError.operationInterrupted.rawValue)
    private let keepOpen = "Couldn't export “Clip”. Keep Chiptune open while the video renders."

    func testAnInterruptedWriterSaysToKeepTheAppOpen() {
        XCTAssertEqual(WriteFailureMessage.export(name: "Clip", error: interrupted, format: .video,
                                                  leftForeground: false), keepOpen)
    }

    /// An interruption wrapped in another error is still one.
    func testAWrappedInterruptionSaysToKeepTheAppOpen() {
        let wrapped = NSError(domain: AVFoundationErrorDomain, code: AVError.unknown.rawValue,
                              userInfo: [NSUnderlyingErrorKey: interrupted])
        XCTAssertEqual(WriteFailureMessage.export(name: "Clip", error: wrapped, format: .video,
                                                  leftForeground: false), keepOpen)
    }

    /// The encoder gives up in the background with whatever error it likes.
    func testAnyFailureAfterLeavingTheAppSaysToKeepItOpen() {
        XCTAssertEqual(WriteFailureMessage.export(name: "Clip", error: generic, format: .video,
                                                  leftForeground: true), keepOpen)
    }

    func testAFailureThatStayedOnScreenIsTheUsualMessage() {
        XCTAssertEqual(WriteFailureMessage.export(name: "Clip", error: generic, format: .video,
                                                  leftForeground: false),
                       "Couldn't export “Clip”. The video couldn't be written. Try again.")
    }

    /// A full disk is a full disk wherever the app was.
    func testANamedCauseWinsOverLeavingTheApp() {
        let full = NSError(domain: AVFoundationErrorDomain, code: AVError.diskFull.rawValue)
        XCTAssertEqual(WriteFailureMessage.export(name: "Clip", error: full, format: .video,
                                                  leftForeground: true),
                       "Couldn't export “Clip”. There isn't enough free space to write the video. Try again.")
    }

    /// A WAV renders on the CPU and carries on in the background.
    func testAWavIsNeverToldToKeepTheAppOpen() {
        XCTAssertEqual(WriteFailureMessage.export(name: "Clip", error: generic, format: .wav,
                                                  leftForeground: true),
                       "Couldn't export “Clip”. The WAV file couldn't be written. Try again.")
    }
}

/// A fake that records what the studio asked of it.
final class RecordingKeepAlive: ExportKeepAlive, @unchecked Sendable {
    var begins = 0
    var ends = 0
    var leftForeground = false
    func begin() { begins += 1 }
    func end() -> Bool { ends += 1; return leftForeground }
}

/// The studio holds the screen awake and asks for background time for the
/// length of a video render, and lets both go however the render ends.
@MainActor
final class StudioExportKeepAliveTests: XCTestCase {

    private func studio(_ result: ExportResult, keepAlive: RecordingKeepAlive) -> Studio {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false,
                            renderer: { _ in result }, keepAlive: keepAlive)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }
        return studio
    }

    private var videoOptions: ExportOptions {
        var options = ExportOptions()
        options.format = .video
        return options
    }

    func testAVideoRenderIsKeptAliveAndLetGoOnEveryEnding() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keep.mp4")
        let endings: [(String, ExportResult)] = [
            ("success", .success(url)), ("canceled", .canceled), ("tooLong", .tooLong),
            ("failed", .failed(CocoaError(.fileWriteUnknown))),
        ]
        for (name, result) in endings {
            let keepAlive = RecordingKeepAlive()
            let studio = studio(result, keepAlive: keepAlive)
            studio.export(options: videoOptions)
            XCTAssertEqual(keepAlive.begins, 1, "\(name): kept alive while rendering")
            XCTAssertEqual(keepAlive.ends, 0, "\(name): let go too early")
            waitForExport(studio)
            XCTAssertEqual(keepAlive.ends, 1, "\(name): let go once it ended")
        }
    }

    func testAWavRenderIsLeftAlone() {
        let keepAlive = RecordingKeepAlive()
        let studio = studio(.canceled, keepAlive: keepAlive)
        studio.export()
        waitForExport(studio)
        XCTAssertEqual(keepAlive.begins, 0)
        XCTAssertEqual(keepAlive.ends, 0)
    }

    func testAVideoThatFailedAfterLeavingTheAppSaysToKeepItOpen() {
        let keepAlive = RecordingKeepAlive()
        keepAlive.leftForeground = true
        let studio = studio(.failed(CocoaError(.fileWriteUnknown)), keepAlive: keepAlive)
        studio.export(options: videoOptions)
        waitForExport(studio)
        XCTAssertTrue(studio.exportError?.hasSuffix("Keep Chiptune open while the video renders.") ?? false,
                      studio.exportError ?? "nil")
    }
}
