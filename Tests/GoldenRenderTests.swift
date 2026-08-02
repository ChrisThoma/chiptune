import XCTest
import AVFoundation
@testable import Chiptune

/// A fixed song rendered to `Tests/Fixtures/golden-demo.wav`, re-rendered here
/// and compared sample for sample.
///
/// The golden is a **change detector**, not the correctness oracle. It answers
/// "did the synth's output move?" and nothing else — a wrong-but-stable render
/// would match it happily. The structural assertions below are the oracle: an
/// exact duration derived from the tempo, and per-section level bounds derived
/// from where the notes are. That distinction matters at regeneration time,
/// which is the moment a golden test either earns its keep or becomes a rubber
/// stamp: the structural tests must still pass against the new fixture, and the
/// diff must have a reason written next to it in the commit.
final class GoldenRenderTests: XCTestCase {

    /// 132 BPM, 16 steps, one pass — see `TestSongs.golden()`.
    private let expectedSamples = Int((44100.0 * 60.0 / (132.0 * 4.0)).rounded()) * 16

    // MARK: Fixture plumbing

    /// The fixture in the repo, which is where regeneration writes. `#filePath`
    /// resolves to this source file, so this works from any checkout without
    /// the test needing to know the build's sandbox layout.
    private var repoFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-demo.wav")
    }

    /// Prefers the copy bundled into the test target, so the test still works
    /// when the sources aren't on the machine running it.
    private func fixtureURL() throws -> URL {
        if let bundled = Bundle(for: GoldenRenderTests.self)
            .url(forResource: "golden-demo", withExtension: "wav") {
            return bundled
        }
        if FileManager.default.fileExists(atPath: repoFixtureURL.path) {
            return repoFixtureURL
        }
        throw XCTSkip("""
            golden-demo.wav is missing, so there is nothing to compare against. \
            testRegenerateGolden writes it; re-run the suite and this test will \
            have a fixture.
            """)
    }

    /// True when the fixture should be (re)written.
    ///
    /// The env var is the deliberate path — it's declared on the Chiptune
    /// scheme, switched off, so it can be ticked on in Xcode's scheme editor.
    /// (Passing it on the `xcodebuild` command line does *not* work: a unit
    /// test bundle is hosted inside the app and takes its environment from the
    /// scheme, not from the shell.)
    ///
    /// A missing fixture also triggers it, so a checkout without one
    /// bootstraps itself instead of leaving the whole suite permanently
    /// skipped — the run says plainly that it regenerated.
    private var shouldRegenerate: Bool {
        if ProcessInfo.processInfo.environment["CHIPTUNE_REGEN_GOLDEN"] == "1" { return true }
        return !FileManager.default.fileExists(atPath: repoFixtureURL.path)
    }

    /// Reads a 16-bit mono WAV back as its raw integer samples. Deliberately
    /// not routed through `AVAudioFile`: comparing at the stored integers is
    /// what makes "within 2 LSB" a statement about the file rather than about
    /// a float conversion applied to both sides.
    private func pcm16(_ url: URL) throws -> [Int16] {
        let data = try Data(contentsOf: url)
        func le32(_ offset: Int) -> Int {
            Int(data[offset]) | Int(data[offset + 1]) << 8
                | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        }
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let size = le32(offset + 4)
            if id == "data" {
                let payload = data[(offset + 8)..<min(offset + 8 + size, data.count)]
                return payload.withUnsafeBytes { raw in
                    Array(raw.bindMemory(to: Int16.self))
                }
            }
            offset += 8 + size + (size % 2)
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private func renderGolden() throws -> URL {
        try XCTUnwrap(WavExport.render(song: TestSongs.golden()), "the golden song failed to render")
    }

    // MARK: The oracle — structure

    /// Duration follows from the tempo and the step count, so this is
    /// checkable without any recorded output at all.
    func testGoldenRenderHasTheDurationItsTempoImplies() throws {
        let samples = try pcm16(renderGolden())
        XCTAssertEqual(samples.count, expectedSamples)
    }

    /// Where the notes are is where the level should be. The riff runs
    /// continuously across all four quarters with the bass changing at the
    /// halfway point, so every quarter must be well clear of silence and none
    /// of them may be riding the clipper.
    func testGoldenRenderHasAudioThroughoutAndNoClipping() throws {
        let url = try renderGolden()
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                                count: Int(buffer.frameLength)))

        let quarter = samples.count / 4
        for section in 0..<4 {
            let window = samples[(section * quarter)..<((section + 1) * quarter)]
            let level = RenderHarness.rms(window)
            XCTAssertGreaterThan(level, 0.05, "quarter \(section) is too quiet to be the demo riff")
            XCTAssertLessThan(level, 0.5, "quarter \(section) is unexpectedly hot")
            XCTAssertLessThanOrEqual(RenderHarness.peak(window), 1.0,
                                     "quarter \(section) clips")
        }
        XCTAssertFalse(samples.contains { !$0.isFinite })
    }

    // MARK: The change detector

    func testGoldenRenderIsUnchanged() throws {
        let fixture = try pcm16(try fixtureURL())
        let fresh = try pcm16(renderGolden())

        XCTAssertEqual(fresh.count, fixture.count, "the render changed length")
        guard fresh.count == fixture.count else { return }

        // 2 LSB of slack, which is far more than float reassociation can
        // account for (error accumulates to ~1e-11 against an LSB of 3e-5) and
        // far less than any audible change.
        var worst = 0
        var worstIndex = -1
        for i in fresh.indices {
            let delta = abs(Int(fresh[i]) - Int(fixture[i]))
            if delta > worst { worst = delta; worstIndex = i }
        }
        XCTAssertLessThanOrEqual(worst, 2, """
            the synth's output moved: sample \(worstIndex) differs by \(worst) LSB.
            If the change was deliberate, confirm the structural tests above still \
            pass, then regenerate via the scheme's CHIPTUNE_REGEN_GOLDEN and say why in the commit.
            """)
    }

    // MARK: Regeneration

    /// Normally skipped. Writes to the repo rather than the test bundle: the
    /// bundle lives in a build sandbox that gets thrown away, so a fixture
    /// written there would be regenerated into the void.
    func testRegenerateGolden() throws {
        guard shouldRegenerate else {
            throw XCTSkip("the golden fixture is present; tick CHIPTUNE_REGEN_GOLDEN on the scheme to rewrite it")
        }

        let rendered = try renderGolden()
        let destination = repoFixtureURL
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: rendered, to: destination)

        print("Wrote golden fixture to \(destination.path)")
        XCTAssertEqual(try pcm16(destination).count, expectedSamples)
    }
}
