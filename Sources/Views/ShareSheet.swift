import SwiftUI
import UIKit

/// UIActivityViewController wrapper for sharing the exported WAV.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// `completed` is false for both a user cancel and a genuine failure;
    /// `error` distinguishes the two — nil on cancel, set on failure.
    var onComplete: ((_ completed: Bool, _ error: Error?) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // UIKit-presented, so it doesn't inherit the app's forced dark scheme
        // and would otherwise flash white on a light-mode device.
        controller.overrideUserInterfaceStyle = .dark
        controller.completionWithItemsHandler = { _, completed, _, error in
            onComplete?(completed && error == nil, error)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
