import Foundation

/// The words on and behind one grid cell: what it shows, what VoiceOver says,
/// and the names of its effect actions. Shared by the grid and the Grid video
/// so the two can't drift apart.
enum GridCellText {

    /// The cell's text: the note's name, REST for a note-off, a dot for an
    /// empty step. An effect is drawn after it as a mark, not spelled here.
    static func title(note: Int8, effect: NoteEffect) -> String {
        if note == Chip.emptyNote { return "·" }
        return NoteName.label(note)
    }

    /// The effect mark drawn after the title, if any: only a pitch carries one.
    static func mark(note: Int8, effect: NoteEffect) -> NoteEffect? {
        offersEffects(note: note) && effect != .none ? effect : nil
    }

    /// The cell's spoken value: "E5, Vibrato", "E5", "REST" or "Empty".
    static func accessibilityValue(note: Int8, effect: NoteEffect) -> String {
        if note == Chip.emptyNote { return "Empty" }
        let name = NoteName.label(note)
        guard offersEffects(note: note), effect != .none else { return name }
        return "\(name), \(effect.name)"
    }

    /// A VoiceOver action that sets this effect: "Effect: Glide", or
    /// "No effect" to take one off.
    static func actionName(_ effect: NoteEffect) -> String {
        effect == .none ? effect.name : "Effect: \(effect.name)"
    }

    /// Only a pitch can carry an effect; rests and empty steps keep the plain
    /// hold-to-preview.
    static func offersEffects(note: Int8) -> Bool {
        note >= 0
    }
}
