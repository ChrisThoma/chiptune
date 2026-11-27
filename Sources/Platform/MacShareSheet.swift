#if os(macOS)
import AppKit
import SwiftUI

/// The Mac's answer to the iOS share sheet for a finished export or a song
/// file: Save… (a save panel, which is how a Mac keeps a file) or Share… (the
/// system share menu, anchored to its button). Same initializer and the same
/// completion contract as the iOS `ShareSheet`, so ContentView's export flow
/// (`ShareSheetEnding`, the Export panel coming back after a cancel) runs
/// unchanged: `completed` is true once the file is saved or shared, and a
/// cancel reports false with no error.
struct ShareSheet: View {
    let items: [Any]
    var onComplete: ((_ completed: Bool, _ error: Error?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    /// The completion runs once, whichever way out comes first.
    @State private var reported = false

    private var url: URL? { items.first as? URL }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to save")
                        .chipFont(13, weight: .bold)
                        .foregroundStyle(Theme.text)
                    Text(url?.lastPathComponent ?? "")
                        .chipFont(12)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 10) {
                Button("Cancel", role: .cancel) { finish(completed: false, error: nil) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                SharePickerButton(items: items) { completed, error in
                    if completed || error != nil { finish(completed: completed, error: error) }
                }
                .fixedSize()
                Button("Save…") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let url else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportDestination.suggestedName(for: url)
        panel.directoryURL = ExportDestination.directory(for: url)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try ExportDestination.copy(url, to: destination)
                finish(completed: true, error: nil)
            } catch {
                finish(completed: false, error: error)
            }
        }
    }

    private func finish(completed: Bool, error: Error?) {
        guard !reported else { return }
        reported = true
        onComplete?(completed, error)
        dismiss()
    }
}

/// The system share menu, opened from a button so it has something to hang
/// off. Reports `completed` once a service finishes with the file, an error
/// if one fails, and nothing for a menu closed without a pick.
private struct SharePickerButton: NSViewRepresentable {
    let items: [Any]
    let onComplete: (_ completed: Bool, _ error: Error?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Share…", target: context.coordinator,
                              action: #selector(Coordinator.open(_:)))
        button.bezelStyle = .push
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.items = items
        context.coordinator.onComplete = onComplete
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
        var items: [Any] = []
        var onComplete: (Bool, Error?) -> Void = { _, _ in }

        @objc func open(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = self
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        func sharingServicePicker(_ picker: NSSharingServicePicker,
                                  delegateFor service: NSSharingService) -> NSSharingServiceDelegate? {
            self
        }

        func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
            onComplete(true, nil)
        }

        func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            // Closing a service's own window (Mail's compose, say) arrives as
            // a user-cancelled failure, which is a cancel rather than an error.
            if (error as NSError).code == NSUserCancelledError {
                onComplete(false, nil)
            } else {
                onComplete(false, error)
            }
        }
    }
}
#endif
