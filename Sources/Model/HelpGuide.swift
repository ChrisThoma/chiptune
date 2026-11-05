import Foundation

/// The words on the controls the guide quotes. The controls draw these, and
/// `HelpGuideTests` checks the guide against them, so renaming a button fails a
/// test instead of leaving the guide behind.
enum ControlLabel {
    static let patt = "PATT"
    static let song = "SONG"
    static let arrangement = "ARR"
    static let rest = "REST"
    static let presetRow = "Sound"
    static let volume = "Volume"
    static let holdSwitch = "Hold"
    static let decay = "Decay"
    static let reorderDone = "Done"
}

/// The words behind "How it works". Plain data, so `HelpGuideTests` can hold the
/// labels and limits it quotes to the controls they describe.
enum HelpGuide {
    enum SectionID: String, CaseIterable {
        case notes, playing, patterns, arrangement, tracks, sound, songs
    }

    struct Entry: Identifiable, Equatable {
        var id: String { term + (symbol ?? "") }
        let term: String
        var symbol: String? = nil
        let text: String
    }

    struct Section: Identifiable, Equatable {
        let id: SectionID
        let title: String
        let entries: [Entry]
    }

    static let sections: [Section] = [
        Section(id: .notes, title: "Writing notes", entries: [
            Entry(term: "Keys", text: "Tap a key to hear that note and pick it. It stays picked until you choose another."),
            Entry(term: "‹ ›", text: "Move the keys down or up an octave."),
            Entry(term: "Steps", text: "Each row of the grid is one step. Tap a step to place the picked note there. Tap it with the same note picked to clear it, or with another note to change it."),
            Entry(term: "Hold a step", text: "Plays its note without changing anything."),
            Entry(term: "REST", text: "Tap REST, then tap a step, and the sound stops there. Tap REST again to go back to your note."),
        ]),
        Section(id: .playing, title: "Playing", entries: [
            Entry(term: "Play", symbol: "play.fill", text: "Starts and stops playback."),
            Entry(term: "PATT", text: "Loops the pattern you're working on."),
            Entry(term: "SONG", text: "Loops your entire arrangement."),
            Entry(term: "ARR", text: "Opens the arrangement, where you set the order your patterns play in."),
            Entry(term: "BPM", text: "Sets the speed. Tap the number to type one from 40 to 300."),
        ]),
        Section(id: .patterns, title: "Patterns", entries: [
            Entry(term: "A B C", text: "Each letter is a pattern, a short loop of steps. Tap one to edit it. Hold one to rename, duplicate, clear or delete it."),
            Entry(term: "+", text: "Adds a new pattern, up to 16, and puts it at the end of your arrangement."),
            Entry(term: "STEPS", text: "Sets how long this pattern is, from 4 to 64 steps."),
        ]),
        Section(id: .arrangement, title: "Arrangement", entries: [
            Entry(term: "Play order", text: "The list of sections your song plays through, top to bottom, then around again."),
            Entry(term: "×2", text: "How many times a section plays before moving to the next. Use − and + to change it."),
            Entry(term: "Add section", text: "Adds a pattern to the end of the play order."),
            Entry(term: "Edit", text: "Lets you drag sections into a new order or delete them."),
            Entry(term: "SONG", text: "Close the arrangement and tap SONG above the grid. Now playback runs through the entire song. PATT keeps looping one pattern."),
        ]),
        Section(id: .tracks, title: "Tracks", entries: [
            Entry(term: "Track", text: "Each column of the grid is a track, with its name at the top. A track plays one note at a time."),
            Entry(term: "PU1 PU2", text: "Pulse channels, the bright lead sound. Good for melody. For chords, use more tracks. Arpeggio gives every note on a track the same chord shape."),
            Entry(term: "TRI", text: "Triangle channel, a soft tone that's usually the bass."),
            Entry(term: "NOI", text: "Noise channel, usually the drums."),
            Entry(term: "Tap", text: "Tap a track's name to pick it. Tap it again to open its sound controls. On a large screen held sideways, they may already be open beside the grid."),
            Entry(term: "Mute", symbol: "speaker.wave.2.fill", text: "Silences the track, in WAV and video exports too. A MIDI file may keep its notes, turned all the way down. Tap mute again to undo it."),
            Entry(term: "Hold a track", text: "With two or more tracks, hold a name to reorder them. Drag a name to its new place, then tap Done."),
            Entry(term: "+", text: "Adds a track, up to 8."),
        ]),
        Section(id: .sound, title: "Sound", entries: [
            Entry(term: "Preset", text: "Tap Sound to pick a ready-made sound for this track. The list changes with the Channel. Adjust it with Volume, Decay and the other controls."),
            Entry(term: "Channel", text: "The type of sound this track makes: Pulse 1, Pulse 2, Triangle or Noise. Changing it keeps your notes but resets the track's sound settings."),
            Entry(term: "Volume", text: "How loud the track is."),
            Entry(term: "Hold", text: "Keeps a note sounding until the next note on the track, or a rest."),
            Entry(term: "Decay", text: "How long a note takes to fade out. It's off while Hold is on."),
            Entry(term: "Pulse width", text: "Changes the tone of a pulse channel."),
            Entry(term: "Arpeggio", text: "Cycles through a chord's notes so fast they sound like one voice. In a MIDI file you get the note you wrote."),
        ]),
        Section(id: .songs, title: "Your songs", entries: [
            Entry(term: "Songs", symbol: "music.note.list", text: "Opens your saved songs. Songs save themselves as you go."),
            Entry(term: "Undo", symbol: "arrow.uturn.backward", text: "Takes back your last change. Redo puts it back."),
            Entry(term: "Menu", symbol: "ellipsis.circle.fill", text: "New song, import, export and sharing. Export makes a WAV, a MIDI file or a video."),
        ]),
    ]

    static func section(_ id: SectionID) -> Section? {
        sections.first { $0.id == id }
    }
}
