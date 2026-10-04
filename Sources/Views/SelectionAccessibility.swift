import SwiftUI

/// VoiceOver's half of the highlight on the selected track header, the current
/// piano key and an armed REST. The fill alone told a sighted user which one
/// was picked; without the trait VoiceOver read every header and every key
/// the same.
enum SelectionAccessibility {
    static func traits(selected: Bool) -> AccessibilityTraits {
        selected ? [.isButton, .isSelected] : .isButton
    }
}
