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
    /// Keys stop growing here and center in whatever space is left. Eight
    /// white keys across an iPad's full width would be 150pt each, which
    /// stops reading as a keyboard.
    var keyboardMaxWidth: CGFloat
    /// Points of type for the note names on the key caps.
    var keyLabelSize: CGFloat
    /// Widest the stacked editor — chrome, grid and keys together — is
    /// allowed to get. Past this the whole column centers, rather than pushing
    /// BPM and STEPS half a meter away from the play button they belong
    /// beside. It's one cap for all three so they keep one leading and one
    /// trailing edge: capping the chrome alone left the title and transport
    /// floating in the middle of a grid that ran edge to edge.
    var stackedEditorMaxWidth: CGFloat
    /// Height of the transport/pattern trays and their chips. Phone keeps
    /// `Theme.trayHeight`, which other, non-chrome code still reads directly;
    /// the pad path stops reading that constant and gets its own number.
    var trayHeight: CGFloat
    /// Width of a stepper's minus/plus ends — the whole reason the phone
    /// numbers didn't work on a pad: 38pt of end plus the tray's own height
    /// measured well under 44pt on either axis once the pad grew everything
    /// else.
    var stepperEndWidth: CGFloat
    /// Width of the undo/redo buttons beside the song name. Narrower than
    /// every other target on purpose — see the call site — so it still has
    /// its own metric instead of borrowing one of the others.
    var historyButtonWidth: CGFloat
    /// The tappable square around a title-bar icon (Songs, the ••• menu).
    /// Already 44pt on the phone, so the pad value is the same number; kept
    /// as its own metric so the glyph size beside it has something to sit in.
    var titleIconTargetSize: CGFloat
    /// Point size of the glyph inside that square. Grows a little on the pad
    /// so the icon doesn't look lost in the target around it.
    var titleIconGlyphSize: CGFloat
    /// Width of a PATT or SONG segment in the transport's mode toggle.
    var patternSegmentWidth: CGFloat
    /// Width of the ARR button beside that toggle.
    var arrButtonWidth: CGFloat
    /// Minimum width of a pattern chip in the strip. A floor, not a fixed
    /// size — the chip still grows for a longer name — so this only needed
    /// raising, not restructuring, to clear 44pt on the pad.
    var patternChipWidth: CGFloat
    /// Width of the "+" button that adds a pattern.
    var patternAddWidth: CGFloat
    /// iPad-shaped window rather than phone-shaped. Kept as a stored flag
    /// because a popover's *content* is handed a compact size class whatever
    /// the window is — 400pt of popover is compact by any measure — so the
    /// views inside one can't ask the environment what they're being presented
    /// on. The presenting side reads it from here and passes it down.
    var isRegularWidth: Bool
    /// How wide the keyboard column is in the side arrangement. Stored rather
    /// than a constant because a 13-inch window can afford a wider column than
    /// an 11-inch one without starving the grid.
    var sideColumnWidth: CGFloat
    /// Octaves of piano the keyboard draws. Whatever this is, the octave
    /// buttons and `studio.octave` still name the *lowest* one shown, and the
    /// hardware letter row still plays that one.
    var keyboardOctaves: Int
    /// Grid and keyboard sit side by side rather than stacked. True only when
    /// the window is regular-width, wider than it is tall, and wide enough to
    /// give both halves a usable share.
    var usesSideKeyboard: Bool
    /// About what the title, transport and pattern rows stand together,
    /// measured on device. An estimate rather than a layout input: the views
    /// size themselves, and this only decides whether a window is too short
    /// for the fixed editor (see `scrollsEditor`).
    var chromeHeight: CGFloat
    /// What the stacked arrangement spends under the grid: the divider, the
    /// gaps either side of it, the octave row and the keys. Measured, like
    /// `chromeHeight`.
    var stackedKeysHeight: CGFloat
    /// The window is too short for the fixed editor to show `minimumGridRows`
    /// rows, so the whole editor scrolls instead and the grid gets a floor of
    /// its own. Always stacked: a scrolling side column would have nothing to
    /// scroll against.
    var scrollsEditor = false
    /// The selected track's sound controls live permanently in the side
    /// column instead of arriving over the grid as a sheet. Only the side
    /// arrangement has anywhere to put them.
    var docksInstrumentEditor: Bool { usesSideKeyboard }
    /// Which way the grid and the keys run: one after the other down the
    /// window, or side by side. Only the container's axis changes between the
    /// two, so the chrome, grid and keys keep their place in the view tree
    /// across a rotation rather than being torn down and rebuilt — which took
    /// an export in progress, an open alert and the popovers with them.
    var editorAxis: Axis { usesSideKeyboard ? .horizontal : .vertical }
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
        gridMinColumnWidth: 70,
        gridGutterWidth: 28,
        trackHeaderHeight: 81,
        keyboardHeight: 110,
        keyboardMaxWidth: .infinity,
        keyLabelSize: 9,
        stackedEditorMaxWidth: .infinity,
        trayHeight: Theme.trayHeight,
        stepperEndWidth: 38,
        historyButtonWidth: 34,
        titleIconTargetSize: 44,
        titleIconGlyphSize: 19,
        patternSegmentWidth: 52,
        arrButtonWidth: 48,
        patternChipWidth: 40,
        patternAddWidth: 42,
        isRegularWidth: false,
        sideColumnWidth: sideKeyboardWidth,
        keyboardOctaves: 1,
        usesSideKeyboard: false,
        chromeHeight: 158,
        stackedKeysHeight: 184
    )

    static let pad = ChipLayout(
        gridRowHeight: 52,
        gridMinColumnWidth: 104,
        gridGutterWidth: 38,
        trackHeaderHeight: 96,
        keyboardHeight: 170,
        keyboardMaxWidth: 720,
        keyLabelSize: 11,
        // The widest portrait iPad window (13-inch M4/M5), so every portrait
        // iPad runs edge to edge and only a stacked landscape window —
        // accessibility text, or one too short for the fixed editor —
        // centers.
        stackedEditorMaxWidth: 1032,
        trayHeight: 52,
        stepperEndWidth: 48,
        historyButtonWidth: 44,
        titleIconTargetSize: 44,
        titleIconGlyphSize: 21,
        patternSegmentWidth: 60,
        arrButtonWidth: 56,
        patternChipWidth: 48,
        patternAddWidth: 48,
        isRegularWidth: true,
        sideColumnWidth: sideKeyboardWidth,
        keyboardOctaves: 1,
        usesSideKeyboard: false,
        chromeHeight: 174,
        stackedKeysHeight: 248
    )

    /// The keyboard's own horizontal inset and the gap between white keys, shared
    /// with KeyboardView so the width arithmetic below matches what it draws.
    static let keyboardHorizontalPadding: CGFloat = 10
    static let whiteKeySpacing: CGFloat = 2

    /// Where the keys land inside the keyboard, given the width *inside* its
    /// horizontal padding — which is what KeyboardView's GeometryReader
    /// measures, the padding having been applied outside it.
    ///
    /// White keys are bare shapes in an `HStack(spacing: whiteKeySpacing)`, so
    /// the stack shares the width left over after the gaps equally between
    /// them. Black keys are drawn over that row by offset, and each one belongs
    /// centered on the seam between the two white keys it sits between — the
    /// center of the gap, not of a key boundary. Doing that arithmetic without
    /// the gaps loses a fraction of a point per key, which compounds into a
    /// visible lean by the top of a two-octave keyboard.
    struct KeyboardGeometry {
        /// `(insetWidth - whiteKeySpacing * (n - 1)) / n`: what the HStack gives
        /// each white key once the gaps between them are paid for.
        let whiteWidth: CGFloat
        /// A black key is 0.58 of a white one — the proportion the keyboard has
        /// always drawn, now measured against the right white width.
        let blackWidth: CGFloat

        init(insetWidth: CGFloat, whiteKeys: Int) {
            let keys = CGFloat(max(whiteKeys, 1))
            whiteWidth = (insetWidth - ChipLayout.whiteKeySpacing * (keys - 1)) / keys
            blackWidth = 0.58 * whiteWidth
        }

        /// Leading offset for the black key sitting after white key `after`
        /// (zero-based): the center of the gap that follows that key,
        /// `(after + 1) * (whiteWidth + spacing) - spacing / 2`, less half the
        /// black key's width so the key is centered there rather than starting
        /// there.
        func blackKeyOffset(after: Int) -> CGFloat {
            let spacing = ChipLayout.whiteKeySpacing
            let gapCenter = CGFloat(after + 1) * (whiteWidth + spacing) - spacing / 2
            return gapCenter - blackWidth / 2
        }
    }

    /// Width of one white key in a side column showing `octaves` octaves: seven
    /// keys per octave plus the closing C. Pure, so the 44pt floor can be pinned
    /// by a test instead of discovered on a device. Shares its arithmetic with
    /// `KeyboardGeometry`, which is what the view draws from, so the key this
    /// measures is the key on screen.
    static func whiteKeyWidth(columnWidth: CGFloat, octaves: Int) -> CGFloat {
        let keys = 7 * max(octaves, 1) + 1
        return KeyboardGeometry(insetWidth: columnWidth - 2 * keyboardHorizontalPadding,
                                whiteKeys: keys).whiteWidth
    }

    /// The keyboard column in the wide layout. Narrow enough to leave the grid
    /// most of the window, wide enough that eight white keys stay finger-sized.
    static let sideKeyboardWidth: CGFloat = 400

    /// The column a 13-inch window can afford: two octaves of white keys, so
    /// a bass line and the melody over it are reachable without paging the
    /// octave buttons between them. 708 is fifteen 44pt white keys (two
    /// octaves plus the closing C) plus the fourteen 2pt gaps between them
    /// plus the keyboard's own 20pt of horizontal inset.
    static let wideSideKeyboardWidth: CGFloat = 708

    /// What the grid must have *over* its minimum before the wider column is
    /// worth taking. Spending the last 140pt of a 13-inch window on keys would
    /// buy the second octave by pushing the grid to the edge of usable.
    static let wideSideColumnSlack: CGFloat = 140

    /// Which keyboard column a window of this width gets, and how many octaves
    /// fit in it.
    ///
    /// The rule: two octaves only when
    /// `width - minimumSideGridWidth >= wideSideKeyboardWidth + wideSideColumnSlack`.
    /// On the numbers that means 1358pt and up, so the 13-inch iPad (1366 on the
    /// 12.9-inch, 1376 on the M4/M5) gets two and every 11-inch and 10.9-inch
    /// landscape window (1180–1210) keeps one. Pure, so the boundary can be
    /// pinned by a test rather than discovered on a device.
    static func sideColumn(forWindowWidth width: CGFloat) -> (width: CGFloat, octaves: Int) {
        let spare = width - minimumSideGridWidth
        if spare >= wideSideKeyboardWidth + wideSideColumnSlack {
            return (wideSideKeyboardWidth, 2)
        }
        return (sideKeyboardWidth, 1)
    }

    /// What the grid needs beside that column before splitting is worth it:
    /// the step gutter, four iPad-width track columns, the "+" beside them and
    /// the padding around the lot. Below this the grid is a sliver and the
    /// stacked arrangement — which at least gives it the full width — wins.
    static let minimumSideGridWidth: CGFloat =
        pad.gridGutterWidth + 4 * pad.gridMinColumnWidth + 44 + 12

    /// Width of the "+" button that adds a track, shared with `GridView` so
    /// the row-width arithmetic below matches what it draws.
    static let addColumnWidth: CGFloat = 44

    /// The transport row's fixed pieces, shared with `TransportBar` and
    /// `ChipStepper` so the width arithmetic below matches what they draw.
    static let chromeRowPadding: CGFloat = 12
    static let chromeRowSpacing: CGFloat = 8
    static let playButtonWidth: CGFloat = 56
    static let stepperReadoutMinWidth: CGFloat = 38
    /// The least room the spacer between the mode tray and the BPM stepper
    /// keeps, on top of the row spacing either side of it. Zero: the 16pt of
    /// spacing already parts the two trays, and the 12pt this used to be took
    /// the row to 383pt, past a 375pt iPhone SE. Wider phones never reach the
    /// floor, so the spacer still pushes BPM to the far end there.
    static let transportTrayGap: CGFloat = 0

    /// The narrowest the transport row can draw: play, the PATT/SONG/ARR tray,
    /// the BPM stepper, the spacing and spacer between them and the row's own
    /// padding. Nothing in it compresses, so drawn in a window narrower than
    /// this it would widen the whole stacked editor and push the grid and keys
    /// sideways; `TransportBar` breaks it into rows instead (see
    /// `transportForm`).
    /// `stepperEndScale` is the Dynamic Type ratio the stepper ends grow by.
    func transportRowMinimumWidth(stepperEndScale: CGFloat = 1) -> CGFloat {
        ChipLayout.chromeRowPadding * 2
            + ChipLayout.playButtonWidth
            + transportModeTrayWidth
            + ChipLayout.transportTrayGap
            + transportStepperWidth(stepperEndScale: stepperEndScale)
            // Between play, the mode tray, the spacer and the stepper.
            + ChipLayout.chromeRowSpacing * 3
    }

    /// The narrowest the stacked transport draws: play on its own row, then
    /// the mode tray, then the BPM stepper, so it needs only the widest of the
    /// three. The mode tray stretches when stacked; its fixed row width is an
    /// upper bound on what it needs.
    func transportStackMinimumWidth(stepperEndScale: CGFloat = 1) -> CGFloat {
        ChipLayout.chromeRowPadding * 2
            + max(ChipLayout.playButtonWidth + ChipLayout.chromeRowSpacing,
                  transportModeTrayWidth,
                  transportStepperWidth(stepperEndScale: stepperEndScale))
    }

    /// Whether the single transport row fits a chrome `width` wide. When it
    /// doesn't, `TransportBar` falls back to two rows or the stacked form
    /// whatever the text size (see `transportForm`). The view decides with
    /// `ViewThatFits` against the widths it actually draws; this is the same
    /// sum, so tests can say which wins.
    func transportRowFits(width: CGFloat, stepperEndScale: CGFloat = 1) -> Bool {
        transportRowMinimumWidth(stepperEndScale: stepperEndScale) <= width
    }

    /// The narrowest the two-row transport draws: play and the mode tray at
    /// their row widths side by side, then the BPM stepper full width under
    /// them, so it needs the wider of those two rows.
    func transportTwoRowMinimumWidth(stepperEndScale: CGFloat = 1) -> CGFloat {
        ChipLayout.chromeRowPadding * 2
            + max(ChipLayout.playButtonWidth + ChipLayout.chromeRowSpacing + transportModeTrayWidth,
                  transportStepperWidth(stepperEndScale: stepperEndScale))
    }

    /// The shapes `TransportBar` takes below accessibility text sizes, which
    /// always stack.
    enum TransportForm: Equatable {
        /// Play, the mode tray and BPM on one row.
        case row
        /// Play and the mode tray, then BPM full width under them.
        case twoRows
        /// Play, the mode tray and BPM each on a row of their own.
        case stacked
    }

    /// Which form a chrome `width` wide gets: the single row when it fits,
    /// then two rows, then the stacked form as the last resort. Each step
    /// down costs the grid a row of chrome, so this takes the first that
    /// fits. `TransportBar`'s `ViewThatFits` tries them in the same order.
    func transportForm(width: CGFloat, stepperEndScale: CGFloat = 1) -> TransportForm {
        if transportRowFits(width: width, stepperEndScale: stepperEndScale) {
            return .row
        }
        if transportTwoRowMinimumWidth(stepperEndScale: stepperEndScale) <= width {
            return .twoRows
        }
        return .stacked
    }

    /// PATT and SONG segments, the hairline and ARR.
    private var transportModeTrayWidth: CGFloat {
        patternSegmentWidth * 2 + TrayDivider.width + arrButtonWidth
    }

    /// Two stepper ends and the readout between them.
    private func transportStepperWidth(stepperEndScale: CGFloat) -> CGFloat {
        stepperEndWidth * stepperEndScale * 2 + ChipLayout.stepperReadoutMinWidth
    }

    /// Tracks share the available width evenly while they fit; past that they
    /// take `gridMinColumnWidth` and the row overflows into the horizontal
    /// scroll.
    func gridColumnWidth(available width: CGFloat, tracks: Int, canAddTrack: Bool) -> CGFloat {
        let each = (width - gridRowReserved(tracks: tracks, canAddTrack: canAddTrack))
            / CGFloat(max(tracks, 1))
        return max(gridMinColumnWidth, each)
    }

    /// The full width one grid row draws at, given a column width picked by
    /// `gridColumnWidth(available:tracks:canAddTrack:)` (or the floor itself).
    /// Used to check that the starter track count actually fits, rather than
    /// only that the floor is what it claims to be.
    func gridRowWidth(columnWidth: CGFloat, tracks: Int, canAddTrack: Bool) -> CGFloat {
        columnWidth * CGFloat(tracks) + gridRowReserved(tracks: tracks, canAddTrack: canAddTrack)
    }

    /// Everything in a grid row that isn't a track column: the gutter, the
    /// add button, the 12pt of horizontal padding, and the 2pt gaps between
    /// items — leaving the gaps out clipped the last column by a few points
    /// even when everything "fit".
    private func gridRowReserved(tracks: Int, canAddTrack: Bool) -> CGFloat {
        let items = 1 + tracks + (canAddTrack ? 1 : 0)
        return gridGutterWidth
            + (canAddTrack ? ChipLayout.addColumnWidth : 0)
            + 12
            + CGFloat(items - 1) * 2
    }

    /// Total window width at which the side arrangement becomes possible.
    /// Rotation never lands between these two, but a resized Stage Manager
    /// window or a Slide Over transition can, and a short wide window that
    /// splits on proportions alone leaves the grid whatever is left over.
    static var minimumSideBySideWidth: CGFloat { sideKeyboardWidth + minimumSideGridWidth }

    /// What the size handed to `resolve` is measured through. The on-screen
    /// keyboard is not part of the window: measured through it, a 13-inch
    /// portrait window (1024×1366) comes out about 1024×940 — wider than tall
    /// and past the split threshold — so raising the keyboard to type a name
    /// rebuilt the editor side by side and threw away the very field, alert or
    /// sheet being typed into. Nothing in the editor itself needs lifting
    /// clear of the keys: the song name sits at the top, and every other text
    /// field is in an alert, sheet or popover that avoids the keyboard itself.
    static let measurementIgnoresSafeArea: SafeAreaRegions = .keyboard

    /// Picks the metrics for a window of this size.
    ///
    /// Size class alone isn't enough: an iPad app in a narrow Split View slice
    /// is compact-width and should look like the phone, and the same app at
    /// half width is regular but too tall-and-thin to put the keys beside the
    /// grid. So the class decides which set of numbers, and the proportions
    /// decide the arrangement.
    static func resolve(size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> ChipLayout {
        var layout = horizontalSizeClass == .regular
            ? arrangedPad(size: size)
            : ChipLayout.phone
        if size.height - layout.editorFixedHeight
            < CGFloat(minimumGridRows) * (layout.gridRowHeight + 2) {
            // Too short for the fixed editor in either arrangement, and the
            // side one is no way out — it saves the keys' height but not the
            // chrome's. Back to stacked metrics, scrolled.
            layout = horizontalSizeClass == .regular ? .pad : .phone
            layout.scrollsEditor = true
        }
        return layout
    }

    /// The fewest grid rows the fixed editor is allowed to show. Below this
    /// it's hard to see a part as a part, and the window's height is better
    /// spent scrolling past the chrome to a grid that has room.
    static let minimumGridRows = 4

    /// Everything in the fixed editor that isn't grid rows: the chrome, the
    /// track headers with the gap under them, and either the keys under the
    /// grid or the side arrangement's bottom inset.
    var editorFixedHeight: CGFloat {
        chromeHeight + trackHeaderHeight + 7 + (usesSideKeyboard ? 8 : stackedKeysHeight)
    }

    /// The cap on the editor's column in this arrangement. Beside the keys
    /// the grid column is already narrower than the window, so the chrome
    /// over it takes the whole of it, whatever that is.
    var editorMaxWidth: CGFloat {
        usesSideKeyboard ? .infinity : stackedEditorMaxWidth
    }

    /// Width of the column the editor's chrome, grid and divider share, in a
    /// space `windowWidth` wide. The keys sit in this column too, capped
    /// further by `keyboardMaxWidth`.
    func editorColumnWidth(windowWidth: CGFloat) -> CGFloat {
        min(windowWidth, editorMaxWidth)
    }

    /// The regular-width metrics, in whichever arrangement the window's
    /// proportions pick.
    private static func arrangedPad(size: CGSize) -> ChipLayout {
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

            let column = sideColumn(forWindowWidth: size.width)
            layout.sideColumnWidth = column.width
            layout.keyboardOctaves = column.octaves
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

extension View {
    /// A popover takes its size from its content and has no detents, so it
    /// needs one stated. A sheet does not, and a minimum height taller than
    /// the medium detent would fight the detent it was given.
    ///
    /// The defaults are the instrument editor's numbers, which every popover
    /// in the app was sized by before this moved out of it; screens with more
    /// to show pass their own.
    @ViewBuilder
    func popoverSized(_ apply: Bool,
                      minWidth: CGFloat = 380,
                      idealWidth: CGFloat = 420,
                      minHeight: CGFloat = 420,
                      idealHeight: CGFloat = 520) -> some View {
        if apply {
            modifier(PopoverSize(minWidth: minWidth, idealWidth: idealWidth,
                                 minHeight: minHeight, idealHeight: idealHeight))
        } else {
            self
        }
    }
}

/// How big a popover asks to be at a given Dynamic Type `scale`.
///
/// A popover is the one presentation that doesn't grow itself for Dynamic
/// Type — a sheet gets the screen and can scroll into it — so the ideal size
/// scales, and the system fits that to the window. The minimum doesn't: a
/// scaled floor of 380×420 came to 1180×1300 at AX5, wider than an 834pt
/// portrait iPad, and the content was clipped to a box the window couldn't
/// hold. The forms inside scroll, so the unscaled floor loses nothing.
enum PopoverSizing {
    struct Frame: Equatable {
        var minWidth: CGFloat
        var idealWidth: CGFloat
        var minHeight: CGFloat
        var idealHeight: CGFloat
    }

    static func frame(minWidth: CGFloat, idealWidth: CGFloat,
                      minHeight: CGFloat, idealHeight: CGFloat,
                      scale: CGFloat) -> Frame {
        Frame(minWidth: minWidth, idealWidth: max(idealWidth * scale, minWidth),
              minHeight: minHeight, idealHeight: max(idealHeight * scale, minHeight))
    }
}

private struct PopoverSize: ViewModifier {
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let minHeight: CGFloat
    let idealHeight: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        let frame = PopoverSizing.frame(minWidth: minWidth, idealWidth: idealWidth,
                                        minHeight: minHeight, idealHeight: idealHeight,
                                        scale: scale)
        content.frame(minWidth: frame.minWidth, idealWidth: frame.idealWidth,
                      minHeight: frame.minHeight, idealHeight: frame.idealHeight)
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
