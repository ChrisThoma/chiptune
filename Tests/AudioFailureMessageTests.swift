import AVFoundation
import XCTest
@testable import Chiptune

/// The "Audio unavailable" alert's words. The system's text for a refused
/// session is "(OSStatus error 561017449.)", which says nothing to anyone.
final class AudioFailureMessageTests: XCTestCase {
    private let busy = "Another app or a call is using audio. Try again when it's finished."
    private let plain = "Couldn't start audio. Try again."

    private func osStatus(_ code: AVAudioSession.ErrorCode) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: code.rawValue)
    }

    /// A phone or FaceTime call holds the session; `.playback` isn't mixable,
    /// so activating it is refused with one of these two.
    func testASessionRefusedForACallSaysSo() {
        XCTAssertEqual(AudioFailureMessage.start(error: osStatus(.insufficientPriority)), busy)
        XCTAssertEqual(AudioFailureMessage.start(error: osStatus(.cannotInterruptOthers)), busy)
    }

    /// The real codes, in case the enum ever stops matching them.
    func testTheRawOSStatusCodesMatch() {
        XCTAssertEqual(AudioFailureMessage.start(error: NSError(domain: NSOSStatusErrorDomain, code: 561017449)), busy)
        XCTAssertEqual(AudioFailureMessage.start(error: NSError(domain: NSOSStatusErrorDomain, code: 560557684)), busy)
    }

    func testAnythingElseIsPlainAndPastesNothing() {
        let format = NSError(domain: "Chiptune.AudioEngine", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The audio format could not be created."
        ])
        XCTAssertEqual(AudioFailureMessage.start(error: format), plain)
        XCTAssertEqual(AudioFailureMessage.start(error: osStatus(.mediaServicesFailed)), plain)
        XCTAssertEqual(AudioFailureMessage.start(error: nil), plain)
        // The same code in an unrelated domain is a different error.
        XCTAssertEqual(AudioFailureMessage.start(error: NSError(domain: NSCocoaErrorDomain, code: 561017449)), plain)
    }
}
