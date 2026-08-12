import XCTest
@testable import Chiptune

/// `ChipCore` documents a lock-free contract: the audio thread renders while
/// the main thread rewrites parameters underneath it, and every field is
/// word-sized and independently meaningful so a stale read is harmless and a
/// torn one impossible.
///
/// Until now that was a comment. These tests are the check — a render loop on
/// one thread while another does everything the UI can do, asserting the output
/// stays finite and the core's own bounds hold.
///
/// The suite also runs on its own under Thread Sanitizer in CI, which needs
/// `TSAN_OPTIONS=halt_on_error=0` in the scheme to mean anything: every
/// parameter write here is a race by TSan's reckoning, so on the default
/// setting the process aborted on the first one — the `tempo` write inside
/// `load` — and neither test ever reached an assertion. The CI job read that
/// as a pass, because a report is exactly what it expects to see.
final class ChipCoreConcurrencyTests: XCTestCase {

    /// Songs of varying shape, so `load` is repeatedly changing the track and
    /// pattern counts the render loop is reading.
    private func mutationSongs() -> [Song] {
        var songs: [Song] = []
        for tracks in 1...Chip.maxTracks {
            var song = Song(name: "Concurrent \(tracks)")
            song.tempo = Double(90 + tracks * 20)
            song.tracks = (0..<tracks).map { Track(kind: ChannelKind.allCases[$0 % 4]) }
            song.patterns = (0..<3).map { index in
                var pattern = Pattern(name: "\(index)", length: 4 + index * 6, trackCount: tracks)
                for track in 0..<tracks {
                    pattern.rows[track][index] = Int8(48 + track * 3)
                }
                return pattern
            }
            song.arrangement = song.patterns.map { SongSection(patternID: $0.id, repeats: 2) }
            song.normalize()
            songs.append(song)
        }
        return songs
    }

    func testRenderingSurvivesConcurrentParameterWrites() {
        let core = ChipCore(sampleRate: RenderHarness.sampleRate)
        let songs = mutationSongs()
        core.load(song: songs[3])
        core.setSongMode(true)
        core.start()

        let rendered = expectation(description: "render loop finishes")
        let mutated = expectation(description: "mutation loop finishes")
        // Sized to interleave thoroughly without pinning two cores for
        // seconds: the failure this catches shows up in the first hundred
        // passes if it shows up at all, and a longer soak only makes the
        // simulator unhappy.

        // Written only by the render thread and read only after both loops have
        // finished, so the assertion itself isn't part of what's under test.
        let nonFinite = Counter()
        let frames = 512
        let renderPasses = 600

        DispatchQueue.global(qos: .userInitiated).async {
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            buffer.initialize(repeating: 0, count: frames)
            defer { buffer.deallocate() }
            for _ in 0..<renderPasses {
                core.render(frames: frames, into: buffer)
                for i in 0..<frames where !buffer[i].isFinite { nonFinite.bump() }
            }
            rendered.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for pass in 0..<400 {
                let song = songs[pass % songs.count]
                // Everything an edit can do to the core, in the order the app
                // would do it.
                core.load(song: song)
                core.setChain(song.chain)
                core.focus(pattern: pass % song.patterns.count)
                core.setLength(pattern: pass % Chip.maxPatterns, length: 4 + (pass % 60))
                core.setNote(pattern: pass % Chip.maxPatterns,
                             track: pass % Chip.maxTracks,
                             step: pass % Chip.maxSteps,
                             note: Int8(36 + pass % 60))
                for track in song.tracks.indices {
                    core.setInstrument(song.tracks[track].instrument,
                                       kind: song.tracks[track].kind,
                                       track: track,
                                       muted: pass % 7 == 0)
                }
                core.setSongMode(pass % 3 != 0)
                core.tempo = Double(60 + pass % 240)
                // Editing a cell can cut the voice it started, so a release
                // races the render loop the same way every write above does.
                core.release(track: pass % Chip.maxTracks)
                _ = core.ringingSource(track: pass % Chip.maxTracks)
                if pass % 11 == 0 { core.releaseAll() }
            }
            mutated.fulfill()
        }

        wait(for: [rendered, mutated], timeout: 120)

        XCTAssertEqual(nonFinite.value, 0,
                       "the render produced non-finite samples while parameters were being written")
        // The audio thread indexes fixed-size buffers off these, so they going
        // out of range is a memory-safety bug, not a wrong note.
        XCTAssertTrue((1...Int32(Chip.maxTracks)).contains(core.trackCount))
        XCTAssertTrue((1...Int32(Chip.maxPatterns)).contains(core.patternCount))
        XCTAssertTrue((1...Int32(Chip.maxChain)).contains(core.chainCount))
        XCTAssertLessThan(core.currentPattern, Int32(Chip.maxPatterns))
        XCTAssertLessThan(core.currentStep, Int32(Chip.maxSteps))
    }

    /// The chain cursor is advanced by the audio thread at every pattern
    /// boundary and reset by the main thread from `setSongMode` and
    /// `setChain`. The sanitizer judges that pairing by how the advance is
    /// written: a plain stale read is inside the contract, but a main-thread
    /// write landing inside a *long-term* access — the `inout` a compound
    /// assignment like `+=` compiles to — is an exclusivity violation, which
    /// TSan reports as a Swift access race and the CI gate rejects.
    ///
    /// `chainPos = (chainPos + 1) % links` is the benign form: two
    /// instantaneous accesses, nothing held across the arithmetic. This test
    /// is what establishes that rather than taking it on faith, and it is why
    /// the assertion below is about the ordinary contract holding — the
    /// sanitizer's verdict on the run is the other half, and the CI gate owns
    /// it. Run against a build where `start()` still wrote the filter state
    /// directly, the same suite does produce a Swift access race, so the
    /// distinction is real and this suite can see it.
    ///
    /// `testRenderingSurvivesConcurrentParameterWrites` reaches a pattern
    /// boundary only a dozen or so times in a whole run — the songs it loads
    /// are ordinary ones — so it exercises this window almost by accident.
    /// This test exists to make the window wide: a low sample rate, the
    /// highest tempo the core will clamp to, and one-step patterns put a
    /// boundary every 200 samples, so the cursor advances thousands of times
    /// while the other thread does nothing but reset it.
    ///
    /// The sample rate is the lever that makes that possible, and it is a
    /// legitimate one — the core takes it as a parameter and is otherwise
    /// hardware-free, which is the same property every offline DSP assertion
    /// in this suite already relies on.
    func testChainCursorSurvivesResetsWhileTheChainIsAdvancing() {
        // 200 samples a step: 4000 * 60 / (300 * 4).
        let core = ChipCore(sampleRate: 4000)
        var song = Song(name: "Chain churn")
        song.tracks = (0..<2).map { Track(kind: ChannelKind.allCases[$0 % 4]) }
        song.patterns = (0..<4).map { index in
            var pattern = Pattern(name: "\(index)", length: 4, trackCount: 2)
            pattern.rows[0][0] = Int8(48 + index)
            return pattern
        }
        song.arrangement = song.patterns.map { SongSection(patternID: $0.id, repeats: 2) }
        song.normalize()
        core.load(song: song)
        // After `load`, so it is not undone by it. `normalize` will not leave a
        // pattern this short, but the core clamps only at 1.
        for index in 0..<Chip.maxPatterns { core.setLength(pattern: index, length: 1) }
        core.tempo = 300
        core.setSongMode(true)
        core.start()

        let rendered = expectation(description: "render loop finishes")
        let reset = expectation(description: "reset loop finishes")
        let nonFinite = Counter()
        // Counted on the render thread from the value that thread just wrote,
        // and read only after both loops have joined. It is the evidence that
        // the window was actually opened: a run that renders happily without
        // ever crossing a boundary would prove nothing, and would otherwise
        // look exactly like a pass.
        let boundaries = Counter()
        let frames = 256

        DispatchQueue.global(qos: .userInitiated).async {
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            buffer.initialize(repeating: 0, count: frames)
            defer { buffer.deallocate() }
            var last = core.currentPattern
            for _ in 0..<3000 {
                core.render(frames: frames, into: buffer)
                for i in 0..<frames where !buffer[i].isFinite { nonFinite.bump() }
                if core.currentPattern != last {
                    last = core.currentPattern
                    boundaries.bump()
                }
            }
            rendered.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for pass in 0..<20000 {
                // The two main-thread writers of the cursor, and nothing else,
                // so a report from this test can only be about them.
                core.setSongMode(pass % 8 != 0)
                core.setChain(Array(0..<(1 + pass % 4)))
            }
            reset.fulfill()
        }

        wait(for: [rendered, reset], timeout: 120)

        XCTAssertEqual(nonFinite.value, 0,
                       "the render produced non-finite samples while the chain was being reset")
        XCTAssertGreaterThan(boundaries.value, 500,
                             "the render never crossed enough pattern boundaries to exercise the "
                             + "cursor — this test proves nothing unless it does")
        XCTAssertLessThan(core.currentPattern, Int32(Chip.maxPatterns))
        XCTAssertGreaterThanOrEqual(core.currentPattern, 0)
    }

    /// `release` and `releaseAll` bump a per-voice token that the audio thread
    /// reads while triggering notes. The token lives in allocated memory
    /// precisely so the bump would be an ordinary race — but `&+=` on a field
    /// *inside* a pointer element is not an ordinary write. It takes a
    /// modifying access to the element for the duration, which is the
    /// long-term kind Swift enforces, so a concurrent read of that element is
    /// an exclusivity violation rather than a stale value.
    ///
    /// CI caught this where the broad mutation test could not: that test calls
    /// `release` once per pass, against a render loop that only reads the
    /// token when a note actually starts, so the two rarely coincide. Here
    /// every step of every track carries a note at 200 samples a step, so the
    /// audio thread is triggering almost continuously while the other thread
    /// does nothing but bump tokens.
    func testReleaseTokensSurviveConcurrentTriggering() {
        let core = ChipCore(sampleRate: 4000)
        var song = Song(name: "Release churn")
        song.tracks = (0..<Chip.maxTracks).map { Track(kind: ChannelKind.allCases[$0 % 4]) }
        var pattern = Pattern(name: "0", length: 16, trackCount: Chip.maxTracks)
        // A note on every step of every track, so `trigger` runs at every
        // single step boundary rather than at the few that happen to be filled.
        for track in 0..<Chip.maxTracks {
            for step in 0..<16 { pattern.rows[track][step] = Int8(48 + (track + step) % 24) }
        }
        song.patterns = [pattern]
        song.arrangement = [SongSection(patternID: pattern.id, repeats: 1)]
        song.normalize()
        core.load(song: song)
        core.tempo = 300
        core.start()

        let rendered = expectation(description: "render loop finishes")
        let released = expectation(description: "release loop finishes")
        let nonFinite = Counter()
        // Evidence the window was open: a run whose playhead never moved would
        // never trigger, and would otherwise look exactly like a pass.
        let steps = Counter()
        let frames = 256

        DispatchQueue.global(qos: .userInitiated).async {
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            buffer.initialize(repeating: 0, count: frames)
            defer { buffer.deallocate() }
            var last = core.currentStep
            for _ in 0..<3000 {
                core.render(frames: frames, into: buffer)
                for i in 0..<frames where !buffer[i].isFinite { nonFinite.bump() }
                if core.currentStep != last {
                    last = core.currentStep
                    steps.bump()
                }
            }
            rendered.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for pass in 0..<20000 {
                core.release(track: pass % Chip.maxTracks)
                if pass % 4 == 0 { core.releaseAll() }
            }
            released.fulfill()
        }

        wait(for: [rendered, released], timeout: 120)

        XCTAssertEqual(nonFinite.value, 0,
                       "the render produced non-finite samples while release tokens were bumped")
        XCTAssertGreaterThan(steps.value, 500,
                             "the playhead barely moved, so the audio thread was not triggering — "
                             + "this test proves nothing unless it does")
    }

    /// Stopping and starting transport from another thread mid-render is what
    /// the PLAY button does, and `start()` rewrites every voice's state.
    func testTransportChangesDuringRenderStayFinite() {
        let core = ChipCore(sampleRate: RenderHarness.sampleRate)
        core.load(song: TestSongs.golden())
        core.start()

        let rendered = expectation(description: "render loop finishes")
        let toggled = expectation(description: "transport loop finishes")
        let nonFinite = Counter()

        DispatchQueue.global(qos: .userInitiated).async {
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 256)
            buffer.initialize(repeating: 0, count: 256)
            defer { buffer.deallocate() }
            for _ in 0..<1500 {
                core.render(frames: 256, into: buffer)
                for i in 0..<256 where !buffer[i].isFinite { nonFinite.bump() }
            }
            rendered.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for pass in 0..<800 {
                if pass % 2 == 0 { core.start() } else { core.stop() }
                core.audition(track: pass % 4, note: Int8(48 + pass % 40))
                core.finish()
            }
            toggled.fulfill()
        }

        wait(for: [rendered, toggled], timeout: 120)
        XCTAssertEqual(nonFinite.value, 0)
    }
}

/// A counter the render thread bumps and the test reads once both loops have
/// joined. A plain `var` captured by the closure would be a race in the test
/// harness itself, which Thread Sanitizer would report as a finding about
/// nothing.
private final class Counter {
    private let lock = NSLock()
    private var count = 0

    func bump() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
