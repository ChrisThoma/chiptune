import Foundation

/// VoiceOver words for an arrangement row's repeats stepper. The label names
/// the row (1-based, from the current position, matching the pattern menu's
/// "Section N") so four steppers are not four identical "Repeats".
enum RepeatsAccessibility {
    static func label(position: Int) -> String {
        "Section \(position + 1) repeats"
    }

    static func value(_ repeats: Int) -> String {
        repeats == 1 ? "1 time" : "\(repeats) times"
    }
}
