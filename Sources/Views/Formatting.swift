import Foundation

/// Tiny display formatters shared by the export sheet, the library rows, and
/// the arrangement summary — three screens that must describe a song the same
/// way, and used to do it with three copies of the same `String(format:)`.
enum Format {
    /// `1:07` — minutes and zero-padded seconds, rounded. Under ten seconds
    /// it keeps a tenth, `0:01.8`: the starter song exports in 1.8 s, and a
    /// truncated "0:01" undersold it by nearly half.
    static func clock(_ seconds: TimeInterval) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded())
        if tenths > 0, tenths < 100 {
            return String(format: "0:%02d.%d", tenths / 10, tenths % 10)
        }
        let whole = Int(max(seconds, 0).rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// `3 patterns`, `1 pattern`. English-only, like the rest of the UI.
    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// `57%` for a 0...1 level. Rounded, not truncated: `0.57 * 100` lands a
    /// hair under 57, and `Int` of it read a level set to 57 back as 56.
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// `120 BPM`.
    static func bpm(_ tempo: Double) -> String {
        "\(Int(tempo)) BPM"
    }
}
