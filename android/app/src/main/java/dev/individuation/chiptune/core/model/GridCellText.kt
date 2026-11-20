package dev.individuation.chiptune.core.model

/** The words on and behind one grid cell: what it shows, what TalkBack says,
 * and the names of its effect actions (iOS `GridCellText`). Shared by the grid
 * and the Grid video so the two can't drift apart. */
object GridCellText {
    /** The menu's choices, top to bottom: "No effect", then each effect. */
    val menuEffects: List<NoteEffect> = NoteEffect.entries.toList()

    /** The cell's text: the note name ("E5"), REST for a note-off, a dot for
     * an empty step. An effect's mark is drawn after it, see [mark]. */
    @Suppress("UNUSED_PARAMETER")
    fun title(note: Int, effect: NoteEffect): String {
        if (note == Chip.EMPTY_NOTE) return "·"
        return NoteName.label(note)
    }

    /** The effect whose [EffectMark] follows the title, or null for a plain
     * note, a REST or an empty step. */
    fun mark(note: Int, effect: NoteEffect): NoteEffect? =
        if (offersEffects(note) && effect != NoteEffect.NONE) effect else null

    /** One cell of [pattern]; a track or step it doesn't have is empty. */
    fun title(pattern: Pattern, track: Int, step: Int): String = title(note(pattern, track, step), NoteEffect.NONE)

    /** The mark for one cell of [pattern]. */
    fun mark(pattern: Pattern, track: Int, step: Int): NoteEffect? = mark(note(pattern, track, step), pattern.effect(track, step))

    private fun note(pattern: Pattern, track: Int, step: Int): Int =
        pattern.rows.getOrNull(track)?.getOrNull(step) ?: Chip.EMPTY_NOTE

    /** The cell's spoken value: "E5, Vibrato", "E5", "REST" or "Empty". */
    fun accessibilityValue(note: Int, effect: NoteEffect): String {
        if (note == Chip.EMPTY_NOTE) return "Empty"
        val name = NoteName.label(note)
        if (!offersEffects(note) || effect == NoteEffect.NONE) return name
        return "$name, ${effect.displayName}"
    }

    /** A TalkBack action that sets this effect: "Effect: Glide", or
     * "No effect" to take one off. */
    fun actionName(effect: NoteEffect): String =
        if (effect == NoteEffect.NONE) effect.displayName else "Effect: ${effect.displayName}"

    /** Only a pitch can carry an effect; rests and empty steps keep the plain
     * hold-to-preview. */
    fun offersEffects(note: Int): Boolean = note in 0..127
}
