import SwiftUI

/// Confirmation copy that appears at more than one entrance — the ••• menu and
/// a context menu, say — kept in one place so the entrances can't drift apart.
enum ConfirmationCopy {
    static let clearPattern = "Every track's notes in this pattern are erased."
    static let deleteTrack = "Its notes in every pattern go with it. This can't be undone."
}

extension Binding where Value == Bool {
    /// Presentation state derived from an optional: presented while non-nil,
    /// cleared on dismiss. Replaces the hand-rolled get/set pair at every
    /// sheet and alert that presents "whatever this optional holds".
    init<Wrapped>(isPresenting presented: Binding<Wrapped?>) {
        self.init(get: { presented.wrappedValue != nil },
                  set: { if !$0 { presented.wrappedValue = nil } })
    }
}

extension View {
    /// The share sheet for `studio.shareURL`. Attached by both the editor and
    /// the library — the library is itself a sheet, so each needs its own
    /// presenter for the window it is in.
    ///
    /// Sharing the .chipsong is immediate — the file is just the song's
    /// JSON — so it needs no render and no progress.
    func songShareSheet(for studio: Studio) -> some View {
        sheet(isPresented: Binding(isPresenting: Bindable(studio).shareURL)) {
            if let url = studio.shareURL {
                ShareSheet(items: [url])
            }
        }
    }
}

extension View {
    /// Presents `message` as a one-button alert and clears it on dismissal, so
    /// the same failure happening twice shows twice.
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(isPresenting: message)) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
