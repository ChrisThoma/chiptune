import Foundation

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
            Entry(term: "Steps", text: "Each row of the grid is one step. Tap a step to place the picked note there. Tap it again to clear it."),
            Entry(term: "Hold", text: "Hold a step to hear its note without changing anything."),
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
            Entry(term: "×2", text: "How many times a section repeats before moving to the next. Use − and + to change it."),
            Entry(term: "Add section", text: "Adds a pattern to the end of the play order."),
            Entry(term: "Edit", text: "Lets you drag sections into a new order or delete them."),
            Entry(term: "SONG", text: "Switch to SONG to hear the whole arrangement. PATT keeps looping one pattern."),
        ]),
        Section(id: .tracks, title: "Tracks", entries: [
            Entry(term: "PU1 PU2", text: "Pulse channels, the bright lead sound. Good for melody and chords."),
            Entry(term: "TRI", text: "Triangle channel, a soft tone that's usually the bass."),
            Entry(term: "NOI", text: "Noise channel, usually the drums."),
            Entry(term: "Tap", text: "Tap a track to pick it. Tap it again to open its sound. On a wide screen the sound controls stay beside the grid."),
            Entry(term: "Mute", symbol: "speaker.wave.2.fill", text: "Silences the track while you work. Tap it again to bring it back."),
            Entry(term: "Hold", text: "Hold a track, then drag it to move it."),
            Entry(term: "+", text: "Adds a track, up to 8."),
        ]),
        Section(id: .sound, title: "Sound", entries: [
            Entry(term: "Preset", text: "A starting point for the track's sound. Every control below stays yours to move."),
            Entry(term: "Channel", text: "Switches the track between Pulse, Triangle and Noise. Its notes stay."),
            Entry(term: "Volume", text: "How loud the track is."),
            Entry(term: "Hold", text: "Keeps a note sounding until the next note on the track, or a rest."),
            Entry(term: "Decay", text: "How long a note takes to fade out."),
            Entry(term: "Pulse width", text: "Changes the tone of a pulse channel."),
            Entry(term: "Arpeggio", text: "Cycles through a chord's notes so fast they sound like one chord."),
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
