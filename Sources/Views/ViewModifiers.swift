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
    static let clearPattern = "Every track's notes in this pattern are erased."
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
    func songShareSheet(for studio: Studio) -> some View {
        sheet(isPresented: Binding(isPresenting: Bindable(studio).shareURL)) {
            if let url = studio.shareURL {
                ShareSheet(items: [url], onComplete: { _, error in
                    if let error {
                        studio.shareError = "Couldn't share the song file. \(error.localizedDescription)"
                    }
                })
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
