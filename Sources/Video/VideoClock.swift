import Foundation

/// The times a Cartridge video draws. The total is the Export sheet's own
/// text (`Format.clock`), so the file says what the sheet promised. The
/// running clock is in the total's format, keeping a tenth when the total
/// does, so the two read as one clock. It is truncated so it never runs
/// ahead of the audio, and the last frame shows the total so the bar ends
/// on it.
enum VideoClock {
    static func total(_ seconds: Double) -> String { Format.clock(seconds) }

    static func elapsed(_ seconds: Double, total: Double, isFinalFrame: Bool) -> String {
        if isFinalFrame { return Self.total(total) }
        let seconds = max(seconds, 0)
        if Self.total(total).contains(".") {
            // The nudge keeps 0.3 s, which is 2.9999… tenths in binary, at 0.3.
            let tenths = Int(seconds * 10 + 1e-9)
            return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
        }
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
