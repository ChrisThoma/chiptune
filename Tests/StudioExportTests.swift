import XCTest
import AVFoundation
import os
@testable import Chiptune

/// Export from the app's side: kicking it off must return immediately, report
/// progress through `isExporting`, and eventually publish a URL to a real,
/// readable file. A second tap mid-export must not start a second render.
@MainActor
final class StudioExportTests: XCTestCase {

    /// Every `Studio` here goes through a temp store with autosave off. The
    /// default store writes real Documents files and `UserDefaults.standard`,
    /// which would leak this suite's songs into every other suite's `loadAll`
    /// and make the order tests run in matter.
    private func makeStudio() -> Studio {
        let studio = Studio(store: makeTempStore().store, autosaveEnabled: false)
        addTeardownBlock { @MainActor in studio.invalidateTimers() }
        return studio
    }

    func testExportRunsAsyncAndPublishesAPlayableFile() throws {
        let studio = makeStudio()
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
        let studio = makeStudio()
        studio.export()
        XCTAssertTrue(studio.isExporting)

        // A double-tap mid-render must not clear state or spawn another render.
        studio.export()
        XCTAssertTrue(studio.isExporting)

        waitForExport(studio)
        XCTAssertNotNil(studio.exportURL)
    }

    /// The injected renderer is the seam the error-surfacing tests lean on, so
    /// it has to be what export actually calls — not a field that quietly goes
    /// unread while `WavExport` runs regardless.
    func testExportUsesTheInjectedRenderer() throws {
        let studio = makeStudio()
        let standIn = FileManager.default.temporaryDirectory
            .appendingPathComponent("injected-\(UUID().uuidString).wav")
        studio.renderer = { _ in .success(standIn) }

        studio.export()
        waitForExport(studio)

        XCTAssertEqual(studio.exportURL, standIn)
    }

    /// With no options passed, the export takes the ones the sheet keeps, as
    /// Android's does; passed ones still win.
    func testExportWithoutOptionsUsesTheStoredOnes() throws {
        let studio = makeStudio()
        let seen = OSAllocatedUnfairLock<[ExportOptions]>(initialState: [])
        let standIn = FileManager.default.temporaryDirectory
            .appendingPathComponent("injected-\(UUID().uuidString).mid")
        studio.renderer = { request in
            seen.withLock { $0.append(request.options) }
            return .success(standIn)
        }
        studio.exportOptions = ExportOptions(format: .midi, loopCount: 3, tailMode: .ringOut)

        studio.export()
        waitForExport(studio)
        studio.export(options: ExportOptions())
        waitForExport(studio)

        XCTAssertEqual(seen.withLock { $0 }, [studio.exportOptions, ExportOptions()])
    }

    /// The export options are one export's, not the app's: when the flow
    /// ends, the next opening starts at WAV, 1x, Seamless loop.
    func testEndingTheExportFlowPutsTheOptionsBackToTheDefaults() {
        let studio = makeStudio()
        studio.exportOptions = ExportOptions(format: .midi, loopCount: 3, tailMode: .ringOut)

        studio.endExportFlow()

        XCTAssertEqual(studio.exportOptions, ExportOptions())
        XCTAssertEqual(ExportOptions(), ExportOptions(format: .wav, loopCount: 1, tailMode: .seamlessLoop))
    }

    /// Nothing is injected, so this is the dispatcher the app ships with: the
    /// format the sheet picked has to reach the writer.
    func testDefaultRendererFollowsTheChosenFormat() throws {
        let studio = makeStudio()
        studio.song.patterns[0].rows[0][0] = 60
        studio.exportOptions.format = .midi

        studio.export(options: studio.exportOptions)
        waitForExport(studio)

        XCTAssertEqual(try XCTUnwrap(studio.exportURL).pathExtension, "mid")
    }

    func testAMidiExportFailureCallsTheFileAMidiFile() {
        let studio = makeStudio()
        studio.renderer = { _ in .failed(CocoaError(.fileWriteNoPermission)) }
        studio.exportOptions.format = .midi

        studio.export(options: studio.exportOptions)
        waitForExport(studio)

        XCTAssertEqual(studio.exportError?.contains("MIDI file"), true)
        XCTAssertEqual(studio.exportError?.contains("WAV"), false)
    }

    /// Exporting the same song in the same format twice writes the same
    /// path, so the URL alone can't tell the second success from the first.
    /// The attempt counter has to move for each, with the file published.
    func testTwoSuccessesToTheSamePathEachAdvanceTheAttempt() throws {
        let studio = makeStudio()
        let standIn = FileManager.default.temporaryDirectory
            .appendingPathComponent("same-\(UUID().uuidString).mid")
        studio.renderer = { _ in .success(standIn) }

        let first = studio.export()
        waitForExport(studio)
        XCTAssertEqual(studio.completedExportAttempt, first)
        XCTAssertEqual(studio.exportURL, standIn)

        let second = studio.export()
        waitForExport(studio)
        XCTAssertEqual(studio.completedExportAttempt, second)
        XCTAssertEqual(try XCTUnwrap(second), try XCTUnwrap(first) + 1)
        XCTAssertEqual(studio.exportURL, standIn)
    }
}
