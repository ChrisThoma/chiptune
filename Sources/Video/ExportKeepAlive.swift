import UIKit

/// Keeps a video render going while it runs: begun when the render starts,
/// ended once however it finishes. Both are called on the main thread.
protocol ExportKeepAlive: AnyObject, Sendable {
    func begin()
    /// Lets go, and says whether the app left the foreground in between —
    /// what decides if a failed render is blamed on that.
    @discardableResult func end() -> Bool
}

/// The real thing. A video's frames are encoded by VideoToolbox, which iOS
/// takes away from an app in the background, so a long render died if the
/// phone auto-locked or the user switched apps. This keeps the screen from
/// locking for the length of the render, asks for background time so a
/// quick trip to another app needn't end it, and notes whether the app went
/// to the background so the failure can say why.
///
/// UIKit only, so `VideoExport` stays free of it and testable; `Studio`
/// drives it through the protocol. Only ever touched on the main thread.
final class SystemExportKeepAlive: ExportKeepAlive, @unchecked Sendable {
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var idleTimerWasDisabled = false
    private var leftForeground = false
    private var observer: NSObjectProtocol?

    func begin() {
        MainActor.assumeIsolated {
            leftForeground = false
            idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.leftForeground = true
            }
            task = UIApplication.shared.beginBackgroundTask(withName: "Video export") { [weak self] in
                // Out of background time. The render will fail when the
                // encoder goes; the task must still be handed back now.
                MainActor.assumeIsolated { self?.endTask() }
            }
        }
    }

    func end() -> Bool {
        MainActor.assumeIsolated {
            UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            endTask()
        }
        return leftForeground
    }

    @MainActor
    private func endTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
