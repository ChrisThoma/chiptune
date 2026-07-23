import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.09)
    static let panel = Color(red: 0.10, green: 0.10, blue: 0.16)
    static let panelHigh = Color(red: 0.15, green: 0.15, blue: 0.23)
    static let grid = Color(red: 0.20, green: 0.20, blue: 0.30)
    static let text = Color(red: 0.88, green: 0.90, blue: 0.96)
    static let dim = Color(red: 0.50, green: 0.52, blue: 0.62)

    /// One accent per channel, in channel order.
    static let channelColors: [Color] = [
        Color(red: 1.00, green: 0.35, blue: 0.45),   // pulse 1 — red
        Color(red: 1.00, green: 0.78, blue: 0.25),   // pulse 2 — amber
        Color(red: 0.30, green: 0.85, blue: 1.00),   // triangle — cyan
        Color(red: 0.70, green: 0.55, blue: 1.00),   // noise — violet
    ]

    static func color(for channel: Int) -> Color {
        channelColors[min(max(channel, 0), channelColors.count - 1)]
    }

    /// Every 4th step is a beat, so it gets a brighter lane.
    static func rowTint(step: Int) -> Color {
        step % 4 == 0 ? panelHigh : panel
    }
}

extension View {
    func chipFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
    }
}
