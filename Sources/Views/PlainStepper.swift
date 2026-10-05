import SwiftUI

/// A minus/plus pair in a capsule, standing in for the system `Stepper` inside
/// sheets.
///
/// Not the system `Stepper`: on iOS 26 that is a `UIStepper` drawing through a
/// hosted graph of its own, and UIKit never releases one once its sheet
/// closes, so every open and close of ARR or Export kept a stepper alive. Same
/// size as the system one, with the end that has nowhere to go dimmed, and one
/// adjustable element for VoiceOver as it was.
struct PlainStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var isEnabled = true
    let accessibilityLabel: String
    let accessibilityValue: String

    private var canDecrease: Bool { isEnabled && value > range.lowerBound }
    private var canIncrease: Bool { isEnabled && value < range.upperBound }

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: canDecrease) { value -= 1 }
            Divider().frame(height: 18)
            stepButton("plus", enabled: canIncrease) { value += 1 }
        }
        .background(Capsule().fill(Color.secondary.opacity(0.18)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrease { value += 1 }
            case .decrement: if canDecrease { value -= 1 }
            @unknown default: break
            }
        }
        // After the accessibility element is formed, so VoiceOver reads it
        // as dimmed rather than as an adjustable that silently does nothing.
        .disabled(!isEnabled)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 46, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .hoverEffect(.highlight)
        .disabled(!enabled)
    }
}
