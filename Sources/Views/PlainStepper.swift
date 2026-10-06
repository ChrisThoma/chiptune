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
            stepButton("minus", enabled: canDecrease) { step(-1) }
            Divider().frame(height: 18)
            stepButton("plus", enabled: canIncrease) { step(1) }
        }
        .background(Capsule().fill(Color.secondary.opacity(0.18)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(Self.delta(forIncrement: true))
            case .decrement: step(Self.delta(forIncrement: false))
            @unknown default: break
            }
        }
        // Swiping needs VoiceOver; Voice Control and Full Keyboard Access
        // reach the two steps through these. A locked or capped stepper
        // makes them no-ops through `step`, and `.disabled` below dims them.
        .accessibilityAction(named: Self.incrementActionName) { step(Self.delta(forIncrement: true)) }
        .accessibilityAction(named: Self.decrementActionName) { step(Self.delta(forIncrement: false)) }
        // After the accessibility element is formed, so VoiceOver reads it
        // as dimmed rather than as an adjustable that silently does nothing.
        .disabled(!isEnabled)
    }

    /// Worded as the system `Stepper` words its actions.
    static let incrementActionName = "Increment"
    static let decrementActionName = "Decrement"

    static func delta(forIncrement increment: Bool) -> Int { increment ? 1 : -1 }

    /// One step from `value`, held at the ends of `range`; a locked stepper
    /// stays where it is.
    static func stepped(_ value: Int, by delta: Int, in range: ClosedRange<Int>,
                        isEnabled: Bool) -> Int {
        guard isEnabled else { return value }
        return min(max(value + delta, range.lowerBound), range.upperBound)
    }

    private func step(_ delta: Int) {
        value = Self.stepped(value, by: delta, in: range, isEnabled: isEnabled)
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
