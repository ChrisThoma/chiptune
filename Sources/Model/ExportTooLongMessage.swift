import Foundation

/// The "Export failed" alert's words when an export comes back `.tooLong`.
/// Each format has a different limit, so each says its own: a WAV runs out
/// of RIFF header at about 13 hours, a video stops at the ten minutes TikTok
/// takes.
enum ExportTooLongMessage {
    static func text(format: ExportOptions.Format) -> String {
        switch format {
        // A MIDI file never comes back too long; it shares the WAV's words
        // only so the switch stays exhaustive.
        case .wav, .midi:
            return "Too long for one WAV — lower the repeat count."
        case .video:
            return "Videos can be up to 10 minutes long. Lower the repeat count, or export a WAV instead."
        }
    }
}
