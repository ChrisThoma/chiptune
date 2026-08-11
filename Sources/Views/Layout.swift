import SwiftUI

/// Sizes that differ between an iPhone window and an iPad one.
///
/// The editor is one screen with no navigation, so adapting it is a matter of
/// metrics and one structural choice rather than a second set of views: the
/// same grid, keyboard and chrome are laid out from these numbers. Anything
/// that would look wrong at 1194pt wide but right at 393pt lives here, so
/// there's one place to read the iPad layout out of.
///
/// Phone values are the ones the views used before iPad support, so an iPhone
/// build renders exactly as it did.
struct ChipLayout: Equatable {
    /// Height of one step row in the grid.
    var gridRowHeight: CGFloat
    /// Floor for a track column's width; past this the grid scrolls sideways.
    var gridMinColumnWidth: CGFloat
    /// The step-number column down the left of the grid.
    var gridGutterWidth: CGFloat
    /// Track header box, matched by the "+" column beside it.
    var trackHeaderHeight: CGFloat
    /// The white keys, not counting the octave/note row above them.
    var keyboardHeight: CGFloat
    /// Keys stop growing here and centre in whatever space is left. Eight
    /// white keys across an iPad's full width would be 150pt each, which
    /// stops reading as a keyboard.
    var keyboardMaxWidth: CGFloat
    /// Points of type for the note names on the key caps.
    var keyLabelSize: CGFloat
    /// Grid and keyboard sit side by side rather than stacked. True only when
    /// the window is both regular-width and wider than it is tall.
    var usesSideKeyboard: Bool

    static let phone = ChipLayout(
        gridRowHeight: 40,
        gridMinColumnWidth: 74,
        gridGutterWidth: 28,
        trackHeaderHeight: 81,
        keyboardHeight: 110,
        keyboardMaxWidth: .infinity,
        keyLabelSize: 9,
        usesSideKeyboard: false
    )

    static let pad = ChipLayout(
        gridRowHeight: 52,
        gridMinColumnWidth: 104,
        gridGutterWidth: 38,
        trackHeaderHeight: 96,
        keyboardHeight: 170,
        keyboardMaxWidth: 720,
        keyLabelSize: 11,
        usesSideKeyboard: false
    )

    /// The keyboard column in the wide layout. Narrow enough to leave the grid
    /// most of the window, wide enough that eight white keys stay finger-sized.
    static let sideKeyboardWidth: CGFloat = 400

    /// Picks the metrics for a window of this size.
    ///
    /// Size class alone isn't enough: an iPad app in a narrow Split View slice
    /// is compact-width and should look like the phone, and the same app at
    /// half width is regular but too tall-and-thin to put the keys beside the
    /// grid. So the class decides which set of numbers, and the proportions
    /// decide the arrangement.
    static func resolve(size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> ChipLayout {
        guard horizontalSizeClass == .regular else { return .phone }
        var layout = ChipLayout.pad
        layout.usesSideKeyboard = size.width > size.height
        if layout.usesSideKeyboard {
            // The column is already narrow, so the keys take all of it, and
            // they grow taller to fill some of the height a stacked keyboard
            // would never have had.
            layout.keyboardMaxWidth = .infinity
            layout.keyboardHeight = 300
        }
        return layout
    }
}

private struct ChipLayoutKey: EnvironmentKey {
    static let defaultValue = ChipLayout.phone
}

extension EnvironmentValues {
    var chipLayout: ChipLayout {
        get { self[ChipLayoutKey.self] }
        set { self[ChipLayoutKey.self] = newValue }
    }
}
