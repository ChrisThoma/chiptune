import UIKit

/// Small, intentional tactile cues for the instrument's primary actions.
enum Haptics {
    static func gridCell() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func transport() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func exportSucceeded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
