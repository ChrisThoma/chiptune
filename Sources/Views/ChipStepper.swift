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

    var canDecrease: Bool { value > range.lowerBound }
    var canIncrease: Bool { value < range.upperBound }

    var body: some View {
        HStack(spacing: 0) {
            Button { onChange(-1) } label: {
                Image(systemName: "minus").chipFont(13)
                    .frame(width: 38, height: Theme.trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDecrease ? Theme.text : Theme.dim.opacity(0.4))
            .accessibilityLabel("Decrease \(label)")
            .disabled(!canDecrease)

            Group {
                if let onTapValue {
                    Button(action: onTapValue) { readout }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(label) \(value), edit")
                } else {
                    readout.allowsHitTesting(false)
                }
            }

            Button { onChange(1) } label: {
                Image(systemName: "plus").chipFont(13)
                    .frame(width: 38, height: Theme.trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canIncrease ? Theme.text : Theme.dim.opacity(0.4))
            .accessibilityLabel("Increase \(label)")
            .disabled(!canIncrease)
        }
    }

    private var readout: some View {
        VStack(spacing: 0) {
            Text("\(value)").chipFont(15, weight: .bold).foregroundStyle(Theme.text)
            Text(label).chipFont(8).foregroundStyle(Theme.dim)
        }
        .frame(minWidth: 38)
        .frame(height: Theme.trayHeight)
        .contentShape(Rectangle())
    }
}
