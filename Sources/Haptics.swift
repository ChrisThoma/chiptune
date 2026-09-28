import UIKit

/// Small, intentional tactile cues for the instrument's primary actions.
enum Haptics {
    static func gridCell() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func transport() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A long press on a track header picked the tracks up for reordering.
    /// Heavier than a cell tap: the whole header row changed state.
    static func reorderBegan() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A dragged track crossed into another column, the detent a drag
    /// reads by without looking.
    static func reorderStep() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func exportSucceeded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
