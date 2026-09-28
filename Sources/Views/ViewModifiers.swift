import SwiftUI
import UIKit

/// A real UIKit accessibility node for controls that iOS 17 bridges to an
/// empty tab group. Unlike a transparent SwiftUI view, this remains present in
/// the accessibility hierarchy while a segmented picker supplies the pixels
/// and direct-touch behavior above it.
struct AccessibilityAdjustableControl: UIViewRepresentable {
    let label: String
    let value: String
    let adjust: (AccessibilityAdjustmentDirection) -> Void

    func makeUIView(context: Context) -> AdjustableView {
        AdjustableView()
    }

    func updateUIView(_ view: AdjustableView, context: Context) {
        view.accessibilityLabel = label
        view.accessibilityValue = value
        view.adjust = adjust
    }

    final class AdjustableView: UIView {
        var adjust: ((AccessibilityAdjustmentDirection) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityTraits = .adjustable
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func accessibilityIncrement() {
            adjust?(.increment)
        }

        override func accessibilityDecrement() {
            adjust?(.decrement)
        }
    }
}

/// Segmented pickers are bridged to empty tab groups on iOS 17. A concrete
/// UIKit view supplies the missing adjustable accessibility node.
func accessibilitySelector(
    label: String,
    value: String,
    adjust: @escaping (AccessibilityAdjustmentDirection) -> Void
) -> some View {
    AccessibilityAdjustableControl(label: label, value: value, adjust: adjust)
}

/// Confirmation copy that appears at more than one entrance — the ••• menu and
/// a context menu, say — kept in one place so the entrances can't drift apart.
enum ConfirmationCopy {
    static let clearPattern = "Every track's notes in this pattern are erased. Undo brings them back."
    static let clearTrack = "Its notes in the other patterns are left alone. Undo brings them back."
    static let deleteTrack = "Its notes in every pattern go with it. You can undo this."
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

extension ExportOptions.TailMode {
    /// VoiceOver's adjustable increment/decrement, mapped onto the two
    /// endings. Increment moves toward "Ring out", decrement toward "Seamless
    /// loop" — the same order the inline picker lists them in — and clamps at
    /// either end rather than wrapping.
    func adjusted(_ direction: AccessibilityAdjustmentDirection) -> ExportOptions.TailMode {
        switch (self, direction) {
        case (.seamlessLoop, .increment): return .ringOut
        case (.ringOut, .decrement): return .seamlessLoop
        default: return self
        }
    }
}

extension View {
    /// The share sheet for `studio.shareURL`. Attached by both the editor and
    /// the library — the library is itself a sheet, so each needs its own
    /// presenter for the window it is in.
    ///
    /// Sharing the .chipsong is immediate — the file is just the song's
    /// JSON — so it needs no render and no progress.
    ///
    /// A completion failure is reported through `onFailure` when the caller
    /// supplies one (the library claims it onto its own alert state, the same
    /// way it claims storage/import failures) and falls back to
    /// `studio.shareError` otherwise, which is what ContentView's own
    /// presenter reads.
    func songShareSheet(for studio: Studio, onFailure: ((String) -> Void)? = nil) -> some View {
        sheet(isPresented: Binding(isPresenting: Bindable(studio).shareURL)) {
            if let url = studio.shareURL {
                ShareSheet(items: [url], onComplete: { _, error in
                    if let error {
                        let message = "Couldn't share the song file. \(error.localizedDescription)"
                        if let onFailure {
                            onFailure(message)
                        } else {
                            studio.shareError = message
                        }
                    }
                })
            }
        }
    }
}

extension View {
    /// The file importer for bringing a `.chipsong` (or bare JSON) into the
    /// library, shared by the Songs list's Add menu and the editor's •••
    /// menu so the two entrances can't drift apart.
    ///
    /// `onResult` runs after the import attempt, deferred the same one
    /// runloop tick as the attempt itself — presenting an error alert in the
    /// same transaction as the file importer's own dismissal can make SwiftUI
    /// silently drop the alert's presentation. The library uses it to dismiss
    /// on success and claim the failure onto its own alert (see
    /// `SongListView.claimImportError()`); the editor is already showing
    /// whatever's current and reads `studio.importError` directly, so it has
    /// nothing further to do and leaves the default.
    func songFileImporter(isPresented: Binding<Bool>, studio: Studio,
                          onResult: @escaping (Bool) -> Void = { _ in }) -> some View {
        fileImporter(isPresented: isPresented,
                      allowedContentTypes: [SongDocument.contentType, .json],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                DispatchQueue.main.async {
                    onResult(studio.importSong(from: url))
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    studio.importError = error.localizedDescription
                    onResult(false)
                }
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
