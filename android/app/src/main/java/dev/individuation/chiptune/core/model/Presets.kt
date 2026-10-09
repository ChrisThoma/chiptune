package dev.individuation.chiptune.core.model

/** Named starting points for a channel's sound (port of `Presets.swift`).
 * The first of each kind is what a new track of that kind gets. */
data class InstrumentPreset(val name: String, val kind: ChannelKind, val instrument: Instrument) {

    /** Swift's `"\(kind.rawValue).\(name)"`; `ChannelKind` is an `Int` enum, so "0.Lead". */
    val id: String get() = "${kind.rawValue}.$name"

    companion object {
        val ALL: List<InstrumentPreset> = listOf(
            // Pulse 1 — the lead channel.
            InstrumentPreset("Lead", ChannelKind.PULSE1, Instrument(duty = 2, volume = 0.8, decay = 0.35)),
            InstrumentPreset("Blip", ChannelKind.PULSE1, Instrument(duty = 0, volume = 0.75, decay = 0.08)),
            InstrumentPreset("Pluck", ChannelKind.PULSE1, Instrument(duty = 1, volume = 0.8, decay = 0.18)),
            InstrumentPreset("Chord", ChannelKind.PULSE1,
                Instrument(duty = 2, volume = 0.7, decay = 0.5, arpeggio = listOf(0, 4, 7))),
            InstrumentPreset("Pad (holds)", ChannelKind.PULSE1,
                Instrument(duty = 3, volume = 0.55, decay = 1.2, sustain = true)),

            // Pulse 2 — the second voice, quieter.
            InstrumentPreset("Harmony", ChannelKind.PULSE2, Instrument(duty = 1, volume = 0.6, decay = 0.5)),
            InstrumentPreset("Echo", ChannelKind.PULSE2, Instrument(duty = 0, volume = 0.45, decay = 0.9)),
            InstrumentPreset("Stab", ChannelKind.PULSE2, Instrument(duty = 2, volume = 0.65, decay = 0.12)),
            InstrumentPreset("Fifths", ChannelKind.PULSE2,
                Instrument(duty = 1, volume = 0.6, decay = 0.45, arpeggio = listOf(0, 7))),

            // Triangle — the bass channel.
            InstrumentPreset("Bass", ChannelKind.TRIANGLE, Instrument(duty = 2, volume = 0.9, decay = 1.5)),
            InstrumentPreset("Sub", ChannelKind.TRIANGLE, Instrument(duty = 2, volume = 1.0, decay = 0.6)),
            InstrumentPreset("Pluck bass", ChannelKind.TRIANGLE, Instrument(duty = 2, volume = 0.9, decay = 0.22)),
            InstrumentPreset("Octaves", ChannelKind.TRIANGLE,
                Instrument(duty = 2, volume = 0.85, decay = 1.0, arpeggio = listOf(0, 12))),
            InstrumentPreset("Drone (holds)", ChannelKind.TRIANGLE,
                Instrument(duty = 2, volume = 0.8, decay = 1.5, sustain = true)),

            // Noise — percussion.
            InstrumentPreset("Hat", ChannelKind.NOISE, Instrument(duty = 2, volume = 0.5, decay = 0.12)),
            InstrumentPreset("Closed hat", ChannelKind.NOISE, Instrument(duty = 2, volume = 0.4, decay = 0.04)),
            InstrumentPreset("Snare", ChannelKind.NOISE, Instrument(duty = 2, volume = 0.7, decay = 0.25)),
            InstrumentPreset("Kick", ChannelKind.NOISE, Instrument(duty = 2, volume = 0.9, decay = 0.09)),
            InstrumentPreset("Crash", ChannelKind.NOISE, Instrument(duty = 2, volume = 0.6, decay = 1.4)),
        )

        fun presetsFor(kind: ChannelKind): List<InstrumentPreset> = ALL.filter { it.kind == kind }

        /** The preset an instrument still matches exactly, or null ("Custom"). */
        fun matching(instrument: Instrument, kind: ChannelKind): InstrumentPreset? =
            presetsFor(kind).firstOrNull { it.instrument == instrument }
    }
}
