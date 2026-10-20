import Foundation

/// The times a Cartridge video draws. The total is the Export sheet's own
/// text (`Format.clock`), so the file says what the sheet promised. The
/// running clock counts whole seconds, truncated so it never runs ahead of
/// the audio, and the last frame shows the total so the bar ends on it.
enum VideoClock {
    static func total(_ seconds: Double) -> String { Format.clock(seconds) }

    static func elapsed(_ seconds: Double, total: Double, isFinalFrame: Bool) -> String {
        if isFinalFrame { return Self.total(total) }
        let whole = Int(max(seconds, 0))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
