import AVFoundation

/// The "Audio unavailable" alert's words when Play or a note preview can't
/// start the engine. The system's text for a refused session is "(OSStatus
/// error 561017449.)", so it is never pasted; only a busy session is named,
/// because that's the one the user can do something about.
enum AudioFailureMessage {
    static func start(error: Error?) -> String {
        if let error, isSessionBusy(error as NSError) {
            return "Another app or a call is using audio. Try again when it's finished."
        }
        return "Couldn't start audio. Try again."
    }

    /// A phone or FaceTime call holds the audio session, and `.playback`
    /// isn't mixable, so activating it is refused with one of these two.
    static func isSessionBusy(_ ns: NSError) -> Bool {
        guard ns.domain == NSOSStatusErrorDomain else { return false }
        return ns.code == AVAudioSession.ErrorCode.insufficientPriority.rawValue
            || ns.code == AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
    }
}
