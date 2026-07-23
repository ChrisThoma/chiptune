import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.09)
    static let panel = Color(red: 0.10, green: 0.10, blue: 0.16)
    static let panelHigh = Color(red: 0.15, green: 0.15, blue: 0.23)
    static let grid = Color(red: 0.20, green: 0.20, blue: 0.30)
    static let text = Color(red: 0.88, green: 0.90, blue: 0.96)
    static let dim = Color(red: 0.50, green: 0.52, blue: 0.62)
    static let divider = grid.opacity(0.8)

    /// Selected states fill with `text`, so anything drawn on top of them needs
    /// a dark foreground rather than the usual light-on-near-black pair.
    static let onLight = Color(red: 0.06, green: 0.06, blue: 0.10)
    /// `accentGreen` scores 1.1:1 on a `text` fill — invisible. This is the
    /// version for a playing dot sitting on a selected chip.
    static let onLightGreen = Color(red: 0.05, green: 0.45, blue: 0.25)

    static let accentGreen = Color(red: 0.40, green: 0.95, blue: 0.60)
    static let accentRed = Color(red: 1.00, green: 0.40, blue: 0.45)

    /// One height and radius rhythm for the chrome above the grid.
    static let trayRadius: CGFloat = 10
    static let innerRadius: CGFloat = 7
    static let trayHeight: CGFloat = 44
    static let innerHeight: CGFloat = 36

    /// One accent per channel kind. Tracks are coloured by the sound they make,
    /// so two triangle tracks share a colour and are told apart by their number.
    static let channelColors: [Color] = [
        Color(red: 1.00, green: 0.35, blue: 0.45),   // pulse 1 — red
        Color(red: 1.00, green: 0.78, blue: 0.25),   // pulse 2 — amber
        Color(red: 0.30, green: 0.85, blue: 1.00),   // triangle — cyan
        Color(red: 0.70, green: 0.55, blue: 1.00),   // noise — violet
    ]

    static func color(for kind: ChannelKind) -> Color {
        channelColors[min(max(kind.rawValue, 0), channelColors.count - 1)]
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

    /// Groups related controls onto one panel so a row of them reads as a
    /// single object rather than a scatter of identical pills.
    func chipTray() -> some View {
        frame(height: Theme.trayHeight)
            .background(RoundedRectangle(cornerRadius: Theme.trayRadius).fill(Theme.panel))
            // Clipping matters for the scrolling pattern strip: without it the
            // chips slide out over the tray's rounded corners.
            .clipShape(RoundedRectangle(cornerRadius: Theme.trayRadius))
    }
}

/// Hairline between segments inside a `chipTray`.
struct TrayDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}
