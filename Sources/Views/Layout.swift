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
    /// Widest the transport and pattern rows are allowed to get. Past this
    /// they centre in whatever space is left, rather than pushing BPM and
    /// STEPS half a metre away from the play button they belong beside.
    var chromeMaxWidth: CGFloat
    /// iPad-shaped window rather than phone-shaped. Kept as a stored flag
    /// because a popover's *content* is handed a compact size class whatever
    /// the window is — 400pt of popover is compact by any measure — so the
    /// views inside one can't ask the environment what they're being presented
    /// on. The presenting side reads it from here and passes it down.
    var isRegularWidth: Bool
    /// Grid and keyboard sit side by side rather than stacked. True only when
    /// the window is regular-width, wider than it is tall, and wide enough to
    /// give both halves a usable share.
    var usesSideKeyboard: Bool
    /// The selected track's sound controls live permanently in the side
    /// column instead of arriving over the grid as a sheet. Only the side
    /// arrangement has anywhere to put them.
    var docksInstrumentEditor: Bool { usesSideKeyboard }
    /// Anchored to the track header that opened it, keeping the grid visible,
    /// rather than a sheet over the whole editor. The side arrangement docks
    /// the controls instead and needs no popover at all.
    var presentsInstrumentAsPopover: Bool { isRegularWidth && !usesSideKeyboard }

    /// Accessibility Dynamic Type uses one vertically scrolling editor even
    /// in a landscape iPad window. Match the interaction model to that visual
    /// layout so track headers open settings instead of looking for a dock
    /// which is no longer present.
    var withoutDockedInstrumentEditor: ChipLayout {
        var copy = self
        copy.usesSideKeyboard = false
        return copy
    }

    static let phone = ChipLayout(
        gridRowHeight: 40,
        gridMinColumnWidth: 74,
        gridGutterWidth: 28,
        trackHeaderHeight: 81,
        keyboardHeight: 110,
        keyboardMaxWidth: .infinity,
        keyLabelSize: 9,
        chromeMaxWidth: .infinity,
        isRegularWidth: false,
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
        chromeMaxWidth: 720,
        isRegularWidth: true,
        usesSideKeyboard: false
    )

    /// The keyboard column in the wide layout. Narrow enough to leave the grid
    /// most of the window, wide enough that eight white keys stay finger-sized.
    static let sideKeyboardWidth: CGFloat = 400

    /// What the grid needs beside that column before splitting is worth it:
    /// the step gutter, four iPad-width track columns, the "+" beside them and
    /// the padding around the lot. Below this the grid is a sliver and the
    /// stacked arrangement — which at least gives it the full width — wins.
    static let minimumSideGridWidth: CGFloat =
        pad.gridGutterWidth + 4 * pad.gridMinColumnWidth + 44 + 12

    /// Total window width at which the side arrangement becomes possible.
    /// Rotation never lands between these two, but a resized Stage Manager
    /// window or a Slide Over transition can, and a short wide window that
    /// splits on proportions alone leaves the grid whatever is left over.
    static var minimumSideBySideWidth: CGFloat { sideKeyboardWidth + minimumSideGridWidth }

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
            && size.width >= minimumSideBySideWidth
        if layout.usesSideKeyboard {
            // The column is already narrow, so the keys take all of it. They
            // grow a little taller than the stacked keyboard's, but not to
            // fill the column: the selected track's sound controls dock under
            // them, and that's what the rest of the height is for.
            layout.keyboardMaxWidth = .infinity
            layout.keyboardHeight = 220
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

extension View {
    /// Half-height sheets are a phone idiom. On an iPad the same detents
    /// shrink a form sheet to a small floating box adrift in the middle of a
    /// large screen; without them the sheet takes the standard iPad form-sheet
    /// size, which is the size its content was laid out for.
    @ViewBuilder
    func compactSheetDetents(_ apply: Bool) -> some View {
        if apply {
            modifier(CompactSheetDetents())
        } else {
            self
        }
    }
}

/// `.medium` is a fine starting height at ordinary text sizes, but at the
/// accessibility Dynamic Type sizes each Form row is tall enough that the
/// medium detent shows only the first section's heading — the rest of the
/// editor is reachable only by dragging the sheet up by hand. Starting an
/// accessibility-sized sheet at `.large` instead means the controls are on
/// screen from the moment it opens; `.medium` stays available for anyone who
/// drags back down.
private struct CompactSheetDetents: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection: PresentationDetent = .medium

    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .large], selection: $selection)
            .onAppear {
                if dynamicTypeSize.isAccessibilitySize {
                    selection = .large
                }
            }
    }
}
