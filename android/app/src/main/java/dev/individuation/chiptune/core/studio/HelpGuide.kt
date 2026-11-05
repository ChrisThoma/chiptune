package dev.individuation.chiptune.core.studio

/** The words behind "How it works" (iOS `HelpGuide`; keep the two in step).
 * Plain data, so `HelpGuideTest` can hold the labels and limits it quotes to
 * the controls they describe. */
object HelpGuide {
    enum class SectionId { NOTES, PLAYING, PATTERNS, ARRANGEMENT, TRACKS, SOUND, SONGS }

    /** Drawn on the chip in place of the term, for a control that has no word on it. */
    enum class Icon { PLAY, MUTE, SONGS, UNDO, MENU }

    data class Entry(val term: String, val text: String, val icon: Icon? = null) {
        val key: String get() = term + (icon?.name ?: "")
    }

    data class Section(val id: SectionId, val title: String, val entries: List<Entry>)

    val sections: List<Section> = listOf(
        Section(
            SectionId.NOTES, "Writing notes",
            listOf(
                Entry("Keys", "Tap a key to hear that note and pick it. It stays picked until you choose another."),
                Entry("‹ ›", "Move the keys down or up an octave."),
                Entry("Steps", "Each row of the grid is one step. Tap a step to place the picked note there. Tap it again to clear it."),
                Entry("Hold", "Hold a step to hear its note without changing anything."),
                Entry("REST", "Tap REST, then tap a step, and the sound stops there. Tap REST again to go back to your note."),
            ),
        ),
        Section(
            SectionId.PLAYING, "Playing",
            listOf(
                Entry("Play", "Starts and stops playback.", Icon.PLAY),
                Entry("PATT", "Loops the pattern you're working on."),
                Entry("SONG", "Loops your entire arrangement."),
                Entry("ARR", "Opens the arrangement, where you set the order your patterns play in."),
                Entry("BPM", "Sets the speed. Tap the number to type one from 40 to 300."),
            ),
        ),
        Section(
            SectionId.PATTERNS, "Patterns",
            listOf(
                Entry("A B C", "Each letter is a pattern, a short loop of steps. Tap one to edit it. Hold one to rename, duplicate, clear or delete it."),
                Entry("+", "Adds a new pattern, up to 16, and puts it at the end of your arrangement."),
                Entry("STEPS", "Sets how long this pattern is, from 4 to 64 steps."),
            ),
        ),
        Section(
            SectionId.ARRANGEMENT, "Arrangement",
            listOf(
                Entry("Play order", "The list of sections your song plays through, top to bottom, then around again."),
                Entry("×2", "How many times a section repeats before moving to the next. Use − and + to change it."),
                Entry("Add section", "Adds a pattern to the end of the play order."),
                Entry("Edit", "Lets you drag sections into a new order or delete them."),
                Entry("SONG", "Switch to SONG to hear the whole arrangement. PATT keeps looping one pattern."),
            ),
        ),
        Section(
            SectionId.TRACKS, "Tracks",
            listOf(
                Entry("PU1 PU2", "Pulse channels, the bright lead sound. Good for melody and chords."),
                Entry("TRI", "Triangle channel, a soft tone that's usually the bass."),
                Entry("NOI", "Noise channel, usually the drums."),
                Entry("Tap", "Tap a track to pick it. Tap it again to open its sound. On a wide screen the sound controls stay beside the grid."),
                Entry("Mute", "Silences the track while you work. Tap it again to bring it back.", Icon.MUTE),
                Entry("Hold", "Hold a track, then drag it to move it."),
                Entry("+", "Adds a track, up to 8."),
            ),
        ),
        Section(
            SectionId.SOUND, "Sound",
            listOf(
                Entry("Preset", "A starting point for the track's sound. Every control below stays yours to move."),
                Entry("Channel", "Switches the track between Pulse, Triangle and Noise. Its notes stay."),
                Entry("Volume", "How loud the track is."),
                Entry("Hold", "Keeps a note sounding until the next note on the track, or a rest."),
                Entry("Decay", "How long a note takes to fade out."),
                Entry("Pulse width", "Changes the tone of a pulse channel."),
                Entry("Arpeggio", "Cycles through a chord's notes so fast they sound like one chord."),
            ),
        ),
        Section(
            SectionId.SONGS, "Your songs",
            listOf(
                Entry("Songs", "Opens your saved songs. Songs save themselves as you go.", Icon.SONGS),
                Entry("Undo", "Takes back your last change. Redo puts it back.", Icon.UNDO),
                Entry("Menu", "New song, import, export and sharing. Export makes a WAV, a MIDI file or a video.", Icon.MENU),
            ),
        ),
    )

    fun section(id: SectionId): Section? = sections.firstOrNull { it.id == id }
}
