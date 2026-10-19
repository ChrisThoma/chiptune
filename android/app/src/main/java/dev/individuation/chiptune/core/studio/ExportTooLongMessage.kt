package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.ExportOptions

/** The "Export failed" alert's words when an export comes back too long.
 * Each format has a different limit, so each says its own: a WAV runs out of
 * RIFF header at about 13 hours, a video stops at the ten minutes TikTok
 * takes. Port of `Sources/Model/ExportTooLongMessage.swift`. */
object ExportTooLongMessage {
    fun text(format: ExportOptions.Format): String = when (format) {
        // A MIDI file never comes back too long; it shares the WAV's words
        // only so the when stays exhaustive.
        ExportOptions.Format.WAV, ExportOptions.Format.MIDI -> "Too long for one WAV — lower the repeat count."
        ExportOptions.Format.VIDEO ->
            "Videos can be up to 10 minutes long. Lower the repeat count, or export a WAV instead."
    }
}
