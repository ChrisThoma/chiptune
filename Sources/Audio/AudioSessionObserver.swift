import AVFoundation

/// Watches the audio session for the three things that silence a running
/// engine, and reports them as plain callbacks.
///
/// Deliberately knows nothing about `Studio` or the UI — it turns notifications
/// into intent ("we lost the output device") and lets the caller decide what
/// that means. That is also what makes it testable: a test posts a crafted
/// notification and asserts the callback fired.
final class AudioSessionObserver {

    /// A phone call, an alarm, another app taking the session.
    var onInterruptionBegan: (() -> Void)?
    /// The interruption is over. Note this fires whether or not the system
    /// suggests resuming — the caller decides.
    var onInterruptionEnded: (() -> Void)?
    /// The output device went away: headphones unplugged, Bluetooth
    /// disconnected. Playing on regardless means suddenly blasting the speaker.
    var onOutputDeviceLost: (() -> Void)?
    /// The media server restarted. Every audio object the process holds is now
    /// invalid and the graph has to be rebuilt from scratch.
    var onMediaServicesReset: (() -> Void)?

    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    /// Observers register with `object: nil` so a test can post the
    /// notification itself — the real one comes from the shared
    /// `AVAudioSession`, which a test has no way to make emit these.
    ///
    /// `queue: nil` means handlers run synchronously on whichever thread
    /// posted. The system posts these on the main thread, and a test posting
    /// from the main thread gets the callback before `post` returns, so
    /// assertions need no waiting.
    init(center: NotificationCenter = .default) {
        self.center = center

        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                         object: nil, queue: nil) { [weak self] note in
            self?.handleInterruption(note)
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                         object: nil, queue: nil) { [weak self] note in
            self?.handleRouteChange(note)
        })
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                         object: nil, queue: nil) { [weak self] _ in
            self?.onMediaServicesReset?()
        })
    }

    deinit {
        for token in tokens { center.removeObserver(token) }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began: onInterruptionBegan?()
        case .ended: onInterruptionEnded?()
        @unknown default: break
        }
    }

    /// Branches on the reason alone, and never on the route description.
    ///
    /// Inspecting the previous route would be the more precise check — "was the
    /// thing that went away our output?" — but `AVAudioSessionRouteDescription`
    /// has no public initialiser, so a handler that reads it cannot be driven
    /// from a test at all. `.oldDeviceUnavailable` already means exactly the
    /// case that matters: something we were playing through is gone.
    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable {
            onOutputDeviceLost?()
        }
    }
}
