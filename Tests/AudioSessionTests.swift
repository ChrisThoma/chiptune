import XCTest
import AVFoundation
@testable import Chiptune

/// The system silencing the engine, and the app noticing.
///
/// These post the real notifications by hand. A phone call can't be staged in
/// a test, but the notification it produces can be — which is exactly why the
/// observer branches on the userInfo keys and never on the route description
/// (`AVAudioSessionRouteDescription` has no public initialiser, so a handler
/// that inspected one could not be driven from here at all).
final class AudioSessionObserverTests: XCTestCase {

    /// A private centre, so these posts can't reach the app's real observers
    /// or any other test's.
    private var center: NotificationCenter!
    private var observer: AudioSessionObserver!

    override func setUp() {
        super.setUp()
        center = NotificationCenter()
        observer = AudioSessionObserver(center: center)
    }

    override func tearDown() {
        observer = nil
        center = nil
        super.tearDown()
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue])
    }

    private func postRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }

    func testInterruptionBeganAndEndedAreReportedSeparately() {
        var began = 0, ended = 0
        observer.onInterruptionBegan = { began += 1 }
        observer.onInterruptionEnded = { ended += 1 }

        postInterruption(.began)
        XCTAssertEqual(began, 1)
        XCTAssertEqual(ended, 0)

        postInterruption(.ended)
        XCTAssertEqual(began, 1)
        XCTAssertEqual(ended, 1)
    }

    func testMalformedInterruptionNotificationIsIgnored() {
        var fired = 0
        observer.onInterruptionBegan = { fired += 1 }
        observer.onInterruptionEnded = { fired += 1 }

        center.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: nil)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: ["nonsense": true])

        XCTAssertEqual(fired, 0, "a notification with no type must not be guessed at")
    }

    /// Headphones out is the one route change that has to stop playback. The
    /// others — a new device arriving, a category change — happen constantly
    /// and must not.
    func testOnlyLosingTheOldDeviceStopsPlayback() {
        var lost = 0
        observer.onOutputDeviceLost = { lost += 1 }

        postRouteChange(.newDeviceAvailable)
        postRouteChange(.categoryChange)
        postRouteChange(.override)
        postRouteChange(.routeConfigurationChange)
        XCTAssertEqual(lost, 0, "a routine route change must not stop the music")

        postRouteChange(.oldDeviceUnavailable)
        XCTAssertEqual(lost, 1)
    }

    /// This one carries no userInfo at all.
    func testMediaServicesResetIsReported() {
        var reset = 0
        observer.onMediaServicesReset = { reset += 1 }

        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)

        XCTAssertEqual(reset, 1)
    }

    func testObserversAreRemovedWhenTheObserverGoesAway() {
        var fired = 0
        observer.onInterruptionBegan = { fired += 1 }
        observer = nil

        postInterruption(.began)

        XCTAssertEqual(fired, 0, "a deallocated observer must not keep listening")
    }
}

/// What the app does about it. Driven through the real `NotificationCenter`,
/// because that is the wiring under test.
@MainActor
final class StudioAudioSessionTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    /// Set directly rather than by calling `play()`: whether `AVAudioEngine`
    /// starts depends on the machine, and what's under test here is the
    /// response to the notification, not the engine.
    private func pretendPlaying() {
        studio.isPlaying = true
        studio.playhead = 7
    }

    func testInterruptionStopsPlayback() {
        pretendPlaying()

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])

        XCTAssertFalse(studio.isPlaying, "a phone call must stop the sequencer")
        XCTAssertEqual(studio.playhead, 0)
    }

    /// The interruption ending brings the engine back but not the music. A
    /// song that starts playing by itself when a call ends is startling, and
    /// the phone may well be in a pocket.
    func testInterruptionEndingDoesNotResumePlayback() {
        pretendPlaying()

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])

        XCTAssertFalse(studio.isPlaying, "playback must not resume on its own")
    }

    func testUnpluggingHeadphonesStopsPlayback() {
        pretendPlaying()

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey:
                        AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])

        XCTAssertFalse(studio.isPlaying, "the speaker must not suddenly take over")
    }

    func testARoutineRouteChangeLeavesPlaybackAlone() {
        pretendPlaying()

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey:
                        AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])

        XCTAssertTrue(studio.isPlaying)
    }

    /// After a media services reset every audio object is invalid, so the graph
    /// is rebuilt — and the song has to be pushed into the new one, or the app
    /// comes back alive and silent.
    func testMediaServicesResetRebuildsTheGraphAndRestoresTheSong() {
        var song = TestSongs.golden()
        song.tempo = 174
        song.patterns.append(Pattern(name: "B", length: 8, trackCount: song.tracks.count))
        song.arrangement.append(SongSection(patternID: song.patterns[1].id, repeats: 2))
        studio.open(song)
        pretendPlaying()

        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification,
                                        object: nil)

        XCTAssertFalse(studio.isPlaying)
        let core = studio.engine.core
        XCTAssertEqual(Int(core.trackCount), studio.song.tracks.count)
        XCTAssertEqual(Int(core.patternCount), studio.song.patterns.count)
        XCTAssertEqual(Int(core.chainCount), studio.song.chain.count)
        XCTAssertEqual(core.tempo, 174, "the transport must be pushed into the rebuilt graph")
        // The rebuilt graph must actually render.
        core.start()
        let samples = RenderHarness.renderMono(core, frames: 4096)
        XCTAssertFalse(samples.contains { !$0.isFinite })
    }

    func testBackgroundingStopsTheEngineOnlyWhenIdle() {
        studio.isPlaying = true
        studio.stopEngineIfIdle()
        // Nothing to assert about the engine's internals beyond this: what
        // matters is that a playing app is not silenced by its own bookkeeping.
        XCTAssertTrue(studio.isPlaying)

        studio.isPlaying = false
        studio.stopEngineIfIdle()
        XCTAssertFalse(studio.engine.isRunning)
    }
}
