import SwiftUI

/// −/value/+ control. The value is tappable when `onTapValue` is supplied.
///
/// Draws no background of its own so it can sit inside a shared `chipTray`
/// alongside other controls; standalone uses apply `.chipTray()` themselves.
struct ChipStepper: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void
    var onTapValue: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var trayHeight = Theme.trayHeight
    @ScaledMetric(relativeTo: .body) private var buttonWidth: CGFloat = 38

    var canDecrease: Bool { value > range.lowerBound }
    var canIncrease: Bool { value < range.upperBound }

    var body: some View {
        HStack(spacing: 0) {
            Button { onChange(-1) } label: {
                Image(systemName: "minus").chipFont(13)
                    .frame(width: buttonWidth, height: trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDecrease ? Theme.text : Theme.dim.opacity(0.4))
            .accessibilityLabel("Decrease \(label)")
            .accessibilityValue("Current value \(value)")
            .disabled(!canDecrease)

            Group {
                if let onTapValue {
                    Button(action: onTapValue) { readout }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label)
                        .accessibilityValue("\(value)")
                        .accessibilityHint("Double tap to edit")
                } else {
                    readout
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label)
                        .accessibilityValue("\(value)")
                }
            }

            Button { onChange(1) } label: {
                Image(systemName: "plus").chipFont(13)
                    .frame(width: buttonWidth, height: trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canIncrease ? Theme.text : Theme.dim.opacity(0.4))
            .accessibilityLabel("Increase \(label)")
            .accessibilityValue("Current value \(value)")
            .disabled(!canIncrease)
        }
    }

    private var readout: some View {
        VStack(spacing: 0) {
            // The number is what the user actually needs to verify (tempo,
            // step count); it must never be the part that truncates. Under
            // width pressure the label below gives way instead, matching the
            // titleBar's TextField/button tradeoff.
            Text("\(value)")
                .chipFont(15, weight: .bold)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            Text(label)
                .chipFont(8)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minWidth: 38)
        .frame(height: trayHeight)
        .contentShape(Rectangle())
    }
}
