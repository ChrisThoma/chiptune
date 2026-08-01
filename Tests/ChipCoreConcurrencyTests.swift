import XCTest
@testable import Chiptune

/// `ChipCore` documents a lock-free contract: the audio thread renders while
/// the main thread rewrites parameters underneath it, and every field is
/// word-sized and independently meaningful so a stale read is harmless and a
/// torn one impossible.
///
/// Until now that was a comment. These tests are the check — a render loop on
/// one thread while another does everything the UI can do, asserting the output
/// stays finite and the core's own bounds hold. The suite also runs on its own
/// under Thread Sanitizer in CI.
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
