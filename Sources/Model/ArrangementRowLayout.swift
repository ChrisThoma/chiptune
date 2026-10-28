import SwiftUI

/// How an arrangement row lays out its controls.
///
/// At accessibility text sizes on a 382 pt display the one-line row (number,
/// pattern menu, "xN", stepper) leaves the pattern menu with only its
/// chevrons, so a section's pattern letter was not visible. There the
/// repeat count and stepper move to a second line and nothing is clamped.
enum ArrangementRowLayout: Equatable {
    case oneLine
    case twoLines

    static func choose(for size: DynamicTypeSize) -> ArrangementRowLayout {
        size.isAccessibilitySize ? .twoLines : .oneLine
    }
}
