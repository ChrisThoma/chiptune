import Foundation

/// The presenters that capture state from the current song. Each subview
/// reports its own flag here (via `reportsPresentation`) so the chords have
/// one place to ask, without lifting or duplicating the flags themselves.
struct SongBoundPresenters: Equatable {
    enum Surface: CaseIterable {
        case patternRename, patternClear, patternDelete, tempoAlert, trackSound
        /// The instrument editor's own Clear track and Delete track alerts.
        /// Docked beside the grid the editor is not the popover the grid
        /// reports as `.trackSound`, so it reports these itself.
        case trackClear, trackDelete
        /// The guide holds no song state, but it covers the editor from places
        /// nothing else reports, such as the docked sound panel.
        case guide
    }

    private var active: Set<Surface> = []

    var isPresented: Bool { !active.isEmpty }

    mutating func set(_ surface: Surface, presented: Bool) {
        if presented { active.insert(surface) } else { active.remove(surface) }
    }
}
