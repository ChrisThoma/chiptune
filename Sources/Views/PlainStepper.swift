import SwiftUI

/// A minus/plus pair in a capsule, standing in for the system `Stepper` inside
/// sheets.
///
/// Not the system `Stepper`: on iOS 26 that is a `UIStepper` drawing through a
/// hosted graph of its own, and UIKit never releases one once its sheet
/// closes, so every open and close of ARR or Export kept a stepper alive. The
/// system one's size at the default text size, growing with Dynamic Type up to
/// AX2, with the end that has nowhere to go dimmed, and one adjustable element
/// for VoiceOver as it was.
struct PlainStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var isEnabled = true
    let accessibilityLabel: String
    let accessibilityValue: String

    private var canDecrease: Bool { isEnabled && value > range.lowerBound }
    private var canIncrease: Bool { isEnabled && value < range.upperBound }

    var body: some View {
        // Capped like the grid's and keys' text: at the largest sizes two
        // full-scale buttons would be wider than the row they sit in.
        PlainStepperButtons(canDecrease: canDecrease, canIncrease: canIncrease,
                            decrease: { step(-1) }, increase: { step(1) })
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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

    /// One button's size: the system stepper's 46 × 32 at the default text
    /// size, grown by the Dynamic Type `scale` so the glyph, which grows
    /// with it, stays inside the capsule. Never below the system size.
    static func buttonSize(scale: CGFloat) -> CGSize {
        let scale = max(scale, 1)
        return CGSize(width: 46 * scale, height: 32 * scale)
    }
}

/// The capsule itself. A view of its own so the Dynamic Type cap that
/// `PlainStepper` applies reaches its `ScaledMetric`, which reads the size
/// from the environment it is placed in.
private struct PlainStepperButtons: View {
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let size = PlainStepper.buttonSize(scale: scale)
        HStack(spacing: 0) {
            stepButton("minus", enabled: canDecrease, size: size, action: decrease)
            Divider().frame(height: size.height * 18 / 32)
            stepButton("plus", enabled: canIncrease, size: size, action: increase)
        }
        .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    private func stepButton(_ symbol: String, enabled: Bool, size: CGSize,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .hoverEffect(.highlight)
        .disabled(!enabled)
    }
}
