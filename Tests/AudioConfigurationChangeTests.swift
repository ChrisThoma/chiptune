#if os(macOS)
import XCTest
import AVFoundation
@testable import Chiptune

/// The Mac's one way of losing the engine: the output device changed
/// (headphones in or out, a new default device). AVAudioEngine stops itself
/// and posts a configuration change, and the app has to rebuild and restart
/// rather than keep PLAY lit over silence.
final class AudioConfigurationChangeTests: XCTestCase {

    /// A private center, as in `AudioSessionObserverTests`.
    func testAConfigurationChangeRebuildsTheEngine() {
        let center = NotificationCenter()
        let observer = AudioSessionObserver(center: center)
        var rebuilt = 0
        observer.onMediaServicesReset = { rebuilt += 1 }

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)

        XCTAssertEqual(rebuilt, 1)
    }
}
#endif
