import XCTest
import AVFoundation
@testable import Chiptune

/// Export from the app's side: kicking it off must return immediately, report
/// progress through `isExporting`, and eventually publish a URL to a real,
/// readable file. A second tap mid-export must not start a second render.
@MainActor
final class StudioExportTests: XCTestCase {

    private func waitForExport(_ studio: Studio, timeout: TimeInterval = 60) {
        let done = expectation(description: "export finishes")
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                if !studio.isExporting { done.fulfill() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }

    func testExportRunsAsyncAndPublishesAPlayableFile() throws {
        let studio = Studio()
        studio.exportURL = URL(fileURLWithPath: "/stale/from/last/time.wav")

        studio.export()

        // The call must come back before the render is done: flag up, stale
        // URL gone. (If the render were synchronous, isExporting would
        // already be false here and the stale URL replaced.)
        XCTAssertTrue(studio.isExporting, "export should still be running right after the call returns")
        XCTAssertNil(studio.exportURL, "a stale URL must not survive the start of a new export")

        waitForExport(studio)

        let url = try XCTUnwrap(studio.exportURL, "a finished export must publish a URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testSecondExportWhileBusyIsIgnored() {
        let studio = Studio()
        studio.export()
        XCTAssertTrue(studio.isExporting)

        // A double-tap mid-render must not clear state or spawn another render.
        studio.export()
        XCTAssertTrue(studio.isExporting)

        waitForExport(studio)
        XCTAssertNotNil(studio.exportURL)
    }
}
