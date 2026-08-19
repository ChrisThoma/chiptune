import Foundation

/// Tiny display formatters shared by the export sheet, the library rows, and
/// the arrangement summary — three screens that must describe a song the same
/// way, and used to do it with three copies of the same `String(format:)`.
enum Format {
    /// `1:07` — minutes and zero-padded seconds, truncating.
    static func clock(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    /// `3 patterns`, `1 pattern`. English-only, like the rest of the UI.
    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// `120 BPM`.
    static func bpm(_ tempo: Double) -> String {
        "\(Int(tempo)) BPM"
    }
}
