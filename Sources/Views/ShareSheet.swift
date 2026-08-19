import SwiftUI
import UIKit

/// UIActivityViewController wrapper for sharing the exported WAV.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // UIKit-presented, so it doesn't inherit the app's forced dark scheme
        // and would otherwise flash white on a light-mode device.
        controller.overrideUserInterfaceStyle = .dark
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
