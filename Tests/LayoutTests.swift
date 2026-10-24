import XCTest
import SwiftUI
@testable import Chiptune

/// Which metrics a window of a given size and size class gets.
///
/// The rule this pins down is that neither input decides on its own: the size
/// class picks the numbers, and the proportions pick the arrangement. Getting
/// that wrong is invisible on the device you happened to test on and obvious
/// on every other one — an iPad in a narrow Split View slice drawn with
/// iPad-sized cells, or a portrait iPad with the keyboard in a side column
/// that leaves the grid a sliver.
final class LayoutTests: XCTestCase {

    /// iPad Pro 11-inch, the two ways round.
    private let padPortrait = CGSize(width: 834, height: 1210)
    private let padLandscape = CGSize(width: 1210, height: 834)
    /// iPhone 15 Pro.
    private let phonePortrait = CGSize(width: 393, height: 852)

    func testCompactWidthGetsPhoneMetricsWhateverTheSize() {
        XCTAssertEqual(ChipLayout.resolve(size: phonePortrait, horizontalSizeClass: .compact),
                       .phone)
        // A Split View slice is iPad-sized in one dimension and still compact.
        XCTAssertEqual(ChipLayout.resolve(size: CGSize(width: 320, height: 1210),
                                          horizontalSizeClass: .compact),
                       .phone)
    }

    /// SwiftUI hands back a nil size class before the first layout pass.
    func testUnknownSizeClassFallsBackToPhone() {
        XCTAssertEqual(ChipLayout.resolve(size: padLandscape, horizontalSizeClass: nil), .phone)
    }

    func testRegularWidthGrowsTheGridAndKeys() {
        let layout = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertGreaterThan(layout.gridRowHeight, ChipLayout.phone.gridRowHeight)
        XCTAssertGreaterThan(layout.gridMinColumnWidth, ChipLayout.phone.gridMinColumnWidth)
        XCTAssertGreaterThan(layout.keyboardHeight, ChipLayout.phone.keyboardHeight)
    }

    func testPortraitStacksAndCapsTheKeyboardWidth() {
        let layout = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertFalse(layout.usesSideKeyboard)
        XCTAssertLessThan(layout.keyboardMaxWidth, padPortrait.width,
                          "Keys spread across the full width stop reading as a keyboard")
    }

    func testLandscapeMovesTheKeysBesideTheGrid() {
        let layout = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(layout.usesSideKeyboard)
        // The column is the cap in this arrangement, so the keys fill it.
        XCTAssertEqual(layout.keyboardMaxWidth, .infinity)
        XCTAssertGreaterThan(layout.keyboardHeight,
                             ChipLayout.resolve(size: padPortrait,
                                                horizontalSizeClass: .regular).keyboardHeight)
    }

    /// A square-ish window is the boundary between the two arrangements, and
    /// the tie has to break somewhere: equal sides stack rather than split,
    /// so the grid keeps the full width.
    func testSquareWindowStacks() {
        let layout = ChipLayout.resolve(size: CGSize(width: 900, height: 900),
                                        horizontalSizeClass: .regular)
        XCTAssertFalse(layout.usesSideKeyboard)
    }

    /// The grid has to fit beside the keyboard column with room to spare, or
    /// the side arrangement is worse than the stacked one it replaces.
    func testSideKeyboardLeavesTheGridMostOfTheWindow() {
        let layout = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        let gridWidth = padLandscape.width - layout.sideColumnWidth
        XCTAssertGreaterThan(gridWidth, padLandscape.width * 0.6)
    }

    /// A 13-inch iPad in landscape has width for a second octave without the
    /// grid dropping below what it needs, so the keys get one. Both the 12.9-inch
    /// (1366) and the M4/M5 13-inch (1376) landscape widths qualify.
    func testThirteenInchLandscapeGetsTwoOctavesInAWiderColumn() {
        for size in [CGSize(width: 1366, height: 1024), CGSize(width: 1376, height: 1032)] {
            let layout = ChipLayout.resolve(size: size, horizontalSizeClass: .regular)
            XCTAssertTrue(layout.usesSideKeyboard, "\(size.width)pt landscape should still split")
            XCTAssertEqual(layout.sideColumnWidth, ChipLayout.wideSideKeyboardWidth, "\(size.width)pt")
            XCTAssertEqual(layout.keyboardOctaves, 2, "\(size.width)pt")
        }
    }

    /// An 11-inch iPad splits, but the second octave would come out of the
    /// grid's share, so it keeps the narrow column and one octave.
    func testElevenInchLandscapeKeepsOneOctave() {
        for size in [CGSize(width: 1194, height: 834), CGSize(width: 1210, height: 834)] {
            let layout = ChipLayout.resolve(size: size, horizontalSizeClass: .regular)
            XCTAssertTrue(layout.usesSideKeyboard, "\(size.width)pt landscape should still split")
            XCTAssertEqual(layout.sideColumnWidth, ChipLayout.sideKeyboardWidth, "\(size.width)pt")
            XCTAssertEqual(layout.keyboardOctaves, 1, "\(size.width)pt")
        }
    }

    /// Half of a 13-inch in Split View is regular and tall, so it stacks —
    /// the wider window behind it must not leak a side column into the slice.
    func testHalfWidthSplitViewStillStacks() {
        let layout = ChipLayout.resolve(size: CGSize(width: 683, height: 1024),
                                        horizontalSizeClass: .regular)
        XCTAssertFalse(layout.usesSideKeyboard)
        XCTAssertEqual(layout.keyboardOctaves, 1)
    }

    /// Whatever column a window earns, the grid keeps its minimum beside it.
    func testTheGridKeepsItsMinimumBesideEverySideColumn() {
        for width in stride(from: 600.0, through: 2400.0, by: 1.0) {
            let layout = ChipLayout.resolve(size: CGSize(width: width, height: 800),
                                            horizontalSizeClass: .regular)
            guard layout.usesSideKeyboard else { continue }
            XCTAssertGreaterThanOrEqual(width - layout.sideColumnWidth,
                                        ChipLayout.minimumSideGridWidth,
                                        "\(width)pt window squeezes the grid")
        }
    }

    /// The rule the two column sizes turn on, on its own: the wider column is
    /// only worth taking when the grid can spare it and the slack besides.
    func testTheSecondOctaveNeedsTheWiderColumnPlusSlack() {
        let boundary = ChipLayout.minimumSideGridWidth
            + ChipLayout.wideSideKeyboardWidth + ChipLayout.wideSideColumnSlack

        let wide = ChipLayout.sideColumn(forWindowWidth: boundary)
        XCTAssertEqual(wide.width, ChipLayout.wideSideKeyboardWidth)
        XCTAssertEqual(wide.octaves, 2)

        let narrow = ChipLayout.sideColumn(forWindowWidth: boundary - 1)
        XCTAssertEqual(narrow.width, ChipLayout.sideKeyboardWidth)
        XCTAssertEqual(narrow.octaves, 1)
    }

    /// The hole the proportions rule left open. Rotation never produces a
    /// window this shape, but Stage Manager and Slide Over both can: wider
    /// than tall, still regular, and not wide enough to give the grid anything
    /// worth having once the keyboard column has taken its 400pt.
    func testShortWideWindowStacksRatherThanSqueezingTheGrid() {
        let squat = CGSize(width: ChipLayout.minimumSideBySideWidth - 1, height: 700)
        XCTAssertGreaterThan(squat.width, squat.height,
                             "This case only matters while the proportions say split")
        XCTAssertFalse(ChipLayout.resolve(size: squat, horizontalSizeClass: .regular)
                        .usesSideKeyboard)

        let wideEnough = CGSize(width: ChipLayout.minimumSideBySideWidth, height: 700)
        XCTAssertTrue(ChipLayout.resolve(size: wideEnough, horizontalSizeClass: .regular)
                        .usesSideKeyboard)
    }

    /// The on-screen keyboard takes about 426pt off a 13-inch portrait
    /// window, and what's left is wider than it is tall and past the split
    /// threshold. Measured through the keyboard, raising it to type a song
    /// name rebuilt the editor side by side and threw the field, the tempo
    /// alert and the rename sheet away mid-edit. The size `resolve` reads has
    /// to be the window's, keyboard or not.
    func testTheOnScreenKeyboardCannotChangeTheArrangement() {
        XCTAssertTrue(ChipLayout.measurementIgnoresSafeArea.contains(.keyboard))
        // The home indicator and status bar still count: those are the window.
        XCTAssertFalse(ChipLayout.measurementIgnoresSafeArea.contains(.container))

        let window = CGSize(width: 1024, height: 1366)
        let throughKeyboard = CGSize(width: 1024, height: 940)
        XCTAssertFalse(ChipLayout.resolve(size: window, horizontalSizeClass: .regular)
                        .usesSideKeyboard)
        XCTAssertTrue(ChipLayout.resolve(size: throughKeyboard, horizontalSizeClass: .regular)
                        .usesSideKeyboard,
                      "If this ever stacks, the keyboard stops mattering here and the test can go")
    }

    /// The two arrangements are one editor laid along different axes, not two
    /// editors: rotating swaps the axis and nothing else, so the chrome, grid
    /// and keys keep their place in the view tree, and with it an export in
    /// progress, an open alert or a popover.
    func testTheArrangementIsAnAxisOfOneEditor() {
        XCTAssertEqual(ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular).editorAxis,
                       .vertical)
        XCTAssertEqual(ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular).editorAxis,
                       .horizontal)
        XCTAssertEqual(ChipLayout.resolve(size: phonePortrait, horizontalSizeClass: .compact).editorAxis,
                       .vertical)
        // The accessibility stack lays the keys under the grid whatever the window.
        XCTAssertEqual(ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
                        .withoutDockedInstrumentEditor.editorAxis,
                       .vertical)
    }

    /// The stacked pad editor's chrome, track headers and keys stand about
    /// 525pt whatever the window, so a short Stage Manager window left the
    /// grid less than a row and pushed controls out of the bottom. Below room
    /// for a handful of rows, the editor scrolls instead, with the grid given
    /// a floor of its own.
    func testShortWindowsScrollTheEditorRatherThanStarveTheGrid() {
        for size in [CGSize(width: 900, height: 600), CGSize(width: 1000, height: 500),
                     CGSize(width: 1200, height: 400), CGSize(width: 700, height: 520)] {
            let layout = ChipLayout.resolve(size: size, horizontalSizeClass: .regular)
            XCTAssertTrue(layout.scrollsEditor, "\(size)")
            XCTAssertFalse(layout.usesSideKeyboard,
                           "\(size): the scrolling editor stacks, so nothing may think it's docked")
        }
        // A compact window that short gets the same treatment.
        XCTAssertTrue(ChipLayout.resolve(size: CGSize(width: 400, height: 480),
                                         horizontalSizeClass: .compact).scrollsEditor)
    }

    func testOrdinaryWindowsKeepTheFixedEditor() {
        let windows: [(CGSize, UserInterfaceSizeClass)] = [
            (CGSize(width: 768, height: 1024), .regular),   // iPad mini portrait, roughly
            (CGSize(width: 1024, height: 1322), .regular),  // 13-inch portrait less the bars
            (CGSize(width: 1133, height: 700), .regular),   // iPad mini landscape less the bars
            (CGSize(width: 1376, height: 988), .regular),   // 13-inch landscape less the bars
            (CGSize(width: 683, height: 980), .regular),    // half a 13-inch
            (CGSize(width: 375, height: 647), .compact),    // iPhone SE less the bars
            (CGSize(width: 402, height: 778), .compact),    // iPhone 17 less the bars
        ]
        for (size, sizeClass) in windows {
            XCTAssertFalse(ChipLayout.resolve(size: size, horizontalSizeClass: sizeClass).scrollsEditor,
                           "\(size)")
        }
    }

    /// The rule itself: whatever doesn't scroll leaves the grid at least
    /// `minimumGridRows` rows once its fixed parts are paid for.
    func testEveryFixedEditorLeavesTheGridItsMinimumRows() {
        for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
            for width in stride(from: 320.0, through: 1400.0, by: 20.0) {
                for height in stride(from: 300.0, through: 1400.0, by: 10.0) {
                    let layout = ChipLayout.resolve(size: CGSize(width: width, height: height),
                                                    horizontalSizeClass: sizeClass)
                    guard !layout.scrollsEditor else { continue }
                    let grid = height - layout.editorFixedHeight
                    XCTAssertGreaterThanOrEqual(
                        grid / (layout.gridRowHeight + 2), CGFloat(ChipLayout.minimumGridRows),
                        "\(width)×\(height) \(sizeClass) leaves the grid \(grid)pt")
                }
            }
        }
    }

    /// The threshold has to sit under every window an iPad can actually be
    /// held in landscape at, or rotating one would stack it.
    func testEveryLandscapeIPadIsWideEnoughToSplit() {
        // 11-inch, 13-inch, and the 10th-generation iPad, landscape.
        for width in [1194.0, 1366.0, 1180.0] {
            XCTAssertGreaterThan(width, ChipLayout.minimumSideBySideWidth,
                                 "\(width)pt landscape should still split")
        }
    }

    /// Every white key, in both side columns, has to clear the 44pt tap
    /// target minimum — a 13-inch window's two-octave column is the one that
    /// gets tight.
    func testEveryWhiteKeyIsAtLeast44ptWideInBothSideColumns() {
        let columns: [(width: CGFloat, octaves: Int, name: String)] = [
            (ChipLayout.sideKeyboardWidth, 1, "the one-octave column"),
            (ChipLayout.wideSideKeyboardWidth, 2, "the two-octave column")
        ]
        for column in columns {
            let width = ChipLayout.whiteKeyWidth(columnWidth: column.width, octaves: column.octaves)
            XCTAssertGreaterThanOrEqual(width, 44, "\(column.name) draws keys under 44pt")
        }
    }

    /// A 13-inch iPad's two-octave column still leaves the grid its minimum.
    func testTheGridKeepsItsMinimumOnAThirteenInch() {
        let layout = ChipLayout.resolve(size: CGSize(width: 1366, height: 1024),
                                        horizontalSizeClass: .regular)
        XCTAssertGreaterThanOrEqual(1366 - layout.sideColumnWidth, ChipLayout.minimumSideGridWidth)
    }

    // MARK: Grid column width

    /// A brand-new song's four starter tracks, plus the "+" column, must fit
    /// a 375pt phone without pushing the row into horizontal scroll — the
    /// floor on a track column can't outrun what four columns actually have
    /// room for.
    func testFourStarterTracksFitA375ptPhoneWithoutScrolling() {
        let song = Song(name: "x")
        let layout = ChipLayout.phone
        let width = layout.gridColumnWidth(available: 375, tracks: song.tracks.count,
                                            canAddTrack: song.canAddTrack)
        XCTAssertGreaterThanOrEqual(width, layout.gridMinColumnWidth)
        let total = layout.gridRowWidth(columnWidth: width, tracks: song.tracks.count,
                                         canAddTrack: song.canAddTrack)
        XCTAssertLessThanOrEqual(total, 375)
    }

    // MARK: Chrome tap targets (HIG 1.2, 44pt minimum)

    /// Every chrome control an iPad user taps — tray height, stepper ends,
    /// the history buttons, the title icons — has to clear the 44pt minimum
    /// on both axes. `Theme.trayHeight` and the old literal widths were
    /// phone numbers reused on the iPad without checking.
    func testPadChromeMetricsMeetTheFortyFourPointMinimum() {
        let pad = ChipLayout.pad
        XCTAssertGreaterThanOrEqual(pad.trayHeight, 44)
        XCTAssertGreaterThanOrEqual(pad.stepperEndWidth, 44)
        XCTAssertGreaterThanOrEqual(pad.historyButtonWidth, 44)
        XCTAssertGreaterThanOrEqual(pad.titleIconTargetSize, 44)
        // These two came in narrower than the rest — 40x52 and 42x52,
        // measured on the accessibility tree — so they get their own floor
        // rather than the full 44: 48pt clears the minimum with room for the
        // pattern name inside.
        XCTAssertGreaterThanOrEqual(pad.patternChipWidth, 48)
        XCTAssertGreaterThanOrEqual(pad.patternAddWidth, 48)
    }

    /// The phone path must render exactly as it did before this layout grew
    /// pad-only chrome metrics — these are today's numbers, not new ones.
    func testPhoneChromeMetricsAreUnchanged() {
        let phone = ChipLayout.phone
        XCTAssertEqual(phone.trayHeight, Theme.trayHeight)
        XCTAssertEqual(phone.stepperEndWidth, 38)
        XCTAssertEqual(phone.historyButtonWidth, 34)
        XCTAssertEqual(phone.titleIconTargetSize, 44)
        XCTAssertEqual(phone.titleIconGlyphSize, 19)
        XCTAssertEqual(phone.patternSegmentWidth, 52)
        XCTAssertEqual(phone.arrButtonWidth, 48)
        XCTAssertEqual(phone.patternChipWidth, 40)
        XCTAssertEqual(phone.patternAddWidth, 42)
        XCTAssertEqual(phone.gridMinColumnWidth, 70)
    }

    /// Play button (56) + mode tray (PATT/SONG segments + ARR) + BPM stepper
    /// (two ends plus the readout) all sit in one row that still has to fit a
    /// regular-width half Split View — about 640pt of window minus the
    /// chrome's own horizontal padding.
    func testPadTransportRowFitsAHalfWidthSplitView() {
        let pad = ChipLayout.pad
        let playButtonWidth: CGFloat = 56
        let modeTrayWidth = pad.patternSegmentWidth * 2 + pad.arrButtonWidth
        let stepperWidth = pad.stepperEndWidth * 2 + 38 // the BPM readout itself
        let rowSpacing: CGFloat = 8 + 12 // play/mode gap + mode/stepper spacer
        let total = playButtonWidth + modeTrayWidth + stepperWidth + rowSpacing
        XCTAssertLessThanOrEqual(total, 600)
    }

    /// Nothing in the transport row compresses, so at 383pt it made the
    /// stacked editor 383pt wide on a 375pt iPhone SE: the grid and keys sat
    /// 4pt right of where they belong and the last track column lost 4pt off
    /// the screen edge.
    func testPhoneTransportRowFitsA375ptScreen() {
        XCTAssertLessThanOrEqual(ChipLayout.phone.transportRowMinimumWidth(), 375)
    }

    /// What the stepper ends grow by at extra-extra-extra-large, the largest
    /// non-accessibility text size: 38pt ends measured 57pt on an iPhone SE.
    private let xxxLargeStepperEndScale: CGFloat = 57.0 / 38.0

    /// At standard text the single row is what the SE and the Pro Max show,
    /// unchanged by the stacked fallback.
    func testTransportKeepsOneRowAtStandardTextOnTheSEAndProMax() {
        XCTAssertTrue(ChipLayout.phone.transportRowFits(width: 375, stepperEndScale: 1))
        XCTAssertTrue(ChipLayout.phone.transportRowFits(width: 440, stepperEndScale: 1))
        XCTAssertEqual(ChipLayout.phone.transportForm(width: 375, stepperEndScale: 1), .row)
        XCTAssertEqual(ChipLayout.phone.transportForm(width: 440, stepperEndScale: 1), .row)
    }

    /// The row needs about 409pt at extra-extra-extra-large, which a 440pt
    /// Pro Max still has.
    func testProMaxKeepsOneRowAtLargestStandardText() {
        XCTAssertEqual(ChipLayout.phone.transportForm(width: 440, stepperEndScale: xxxLargeStepperEndScale),
                       .row)
    }

    /// At extra-extra-extra-large the BPM ends grow to 57pt and the row needs
    /// about 409pt. It never compressed, so on a 375pt SE it widened the
    /// stacked editor and shoved the grid and keys 17pt right off the screen.
    /// Three rows fit but left about a step and a half of grid; play and the
    /// mode tray still share a row (241pt), so only BPM drops under them.
    func testTransportTakesTwoRowsWhenTheRowOverflowsAnSEAtLargestStandardText() {
        let phone = ChipLayout.phone
        XCTAssertGreaterThan(phone.transportRowMinimumWidth(stepperEndScale: xxxLargeStepperEndScale), 375)
        XCTAssertFalse(phone.transportRowFits(width: 375, stepperEndScale: xxxLargeStepperEndScale))
        XCTAssertEqual(phone.transportTwoRowMinimumWidth(stepperEndScale: xxxLargeStepperEndScale), 241)
        XCTAssertEqual(phone.transportForm(width: 375, stepperEndScale: xxxLargeStepperEndScale), .twoRows)
    }

    /// A compact iPad window (Slide Over, a narrow Split View slice) is about
    /// 320pt and gets the phone layout. The row's 371pt can't fit there even
    /// at standard text, but play and the mode tray (241pt, which the BPM
    /// stepper under them never outgrows below accessibility sizes) do, so it
    /// takes two rows at every non-accessibility size.
    func testCompactIPadWindowTakesTwoTransportRows() {
        let slideOver = CGSize(width: 320, height: 1210)
        let layout = ChipLayout.resolve(size: slideOver, horizontalSizeClass: .compact)
        XCTAssertEqual(layout, .phone)
        XCTAssertGreaterThan(layout.transportRowMinimumWidth(), slideOver.width)
        XCTAssertFalse(layout.transportRowFits(width: slideOver.width, stepperEndScale: 1))
        XCTAssertLessThanOrEqual(layout.transportTwoRowMinimumWidth(stepperEndScale: 1), slideOver.width)
        XCTAssertLessThanOrEqual(layout.transportTwoRowMinimumWidth(stepperEndScale: xxxLargeStepperEndScale),
                                 slideOver.width)
        XCTAssertEqual(layout.transportForm(width: slideOver.width, stepperEndScale: 1), .twoRows)
        XCTAssertEqual(layout.transportForm(width: slideOver.width, stepperEndScale: xxxLargeStepperEndScale),
                       .twoRows)
    }

    /// Narrower than play and the mode tray side by side, the transport
    /// stacks all three, and the stacked form still fits there.
    func testTransportStacksOnlyWhenTwoRowsDontFit() {
        let phone = ChipLayout.phone
        let twoRows = phone.transportTwoRowMinimumWidth(stepperEndScale: xxxLargeStepperEndScale)
        XCTAssertEqual(phone.transportForm(width: twoRows, stepperEndScale: xxxLargeStepperEndScale), .twoRows)
        XCTAssertEqual(phone.transportForm(width: twoRows - 1, stepperEndScale: xxxLargeStepperEndScale), .stacked)
        XCTAssertLessThanOrEqual(phone.transportStackMinimumWidth(stepperEndScale: xxxLargeStepperEndScale),
                                 twoRows - 1)
    }

    /// Every portrait iPad window, 13-inch down to the mini. The stacked
    /// editor's chrome, grid and keys all share one column, and on these it's
    /// the whole window: the title and transport used to stop at 720pt and
    /// center while the grid ran edge to edge, so nothing lined up with the
    /// grid's leading or trailing edge.
    private var portraitPads: [CGSize] {
        [CGSize(width: 1032, height: 1376),  // 13-inch M4/M5
         CGSize(width: 1024, height: 1366),  // 12.9-inch
         CGSize(width: 834, height: 1210),   // 11-inch
         CGSize(width: 744, height: 1133)]   // mini
    }

    func testStackedEditorSpansTheWholePortraitIPadWindow() {
        for size in portraitPads {
            let layout = ChipLayout.resolve(size: size, horizontalSizeClass: .regular)
            XCTAssertFalse(layout.usesSideKeyboard)
            XCTAssertEqual(layout.editorColumnWidth(windowWidth: size.width), size.width,
                           "\(size): the chrome must reach the grid's edges")
        }
    }

    /// A stacked editor wider than any portrait iPad — accessibility text in
    /// landscape — centers one column rather than spreading the transport a
    /// meter wide, and the grid and keys come in with it so the edges still
    /// agree.
    func testWideStackedEditorCentersOneColumn() {
        let landscape = CGSize(width: 1376, height: 1032)
        let stacked = ChipLayout.resolve(size: landscape, horizontalSizeClass: .regular)
            .withoutDockedInstrumentEditor
        XCTAssertEqual(stacked.editorColumnWidth(windowWidth: landscape.width), 1032)
    }

    /// Beside the keys, the grid column is already narrower than the window,
    /// so the chrome over it takes all of it rather than a cap of its own.
    func testSideArrangementChromeFillsTheGridColumn() {
        let layout = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(layout.usesSideKeyboard)
        let gridColumn = padLandscape.width - layout.sideColumnWidth - 1
        XCTAssertEqual(layout.editorColumnWidth(windowWidth: gridColumn), gridColumn)
    }

    func testPhoneEditorColumnIsTheWholeWindow() {
        for width: CGFloat in [320, 375, 393, 440] {
            XCTAssertEqual(ChipLayout.phone.editorColumnWidth(windowWidth: width), width)
        }
    }

    /// The column getting wider mustn't take the keys with it: eight white
    /// keys across 1032pt are wider than a hand.
    func testThirteenInchPortraitStillCapsTheKeys() {
        let size = portraitPads[0]
        let layout = ChipLayout.resolve(size: size, horizontalSizeClass: .regular)
        XCTAssertLessThan(layout.keyboardMaxWidth, size.width)
    }

    /// Where the sound controls go, which is one choice with three answers and
    /// no overlap between them: docked in the side column, anchored to the
    /// track header as a popover, or presented as a sheet.
    func testTheInstrumentEditorGoesExactlyOnePlacePerLayout() {
        let landscape = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(landscape.docksInstrumentEditor)
        XCTAssertFalse(landscape.presentsInstrumentAsPopover)

        let portrait = ChipLayout.resolve(size: padPortrait, horizontalSizeClass: .regular)
        XCTAssertFalse(portrait.docksInstrumentEditor)
        XCTAssertTrue(portrait.presentsInstrumentAsPopover)

        // The phone keeps the sheet it has always had.
        let phone = ChipLayout.resolve(size: phonePortrait, horizontalSizeClass: .compact)
        XCTAssertFalse(phone.docksInstrumentEditor)
        XCTAssertFalse(phone.presentsInstrumentAsPopover)
    }

    func testAccessibilityStackMakesTheLandscapeInstrumentEditorReachable() {
        let landscape = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertTrue(landscape.docksInstrumentEditor, "precondition")

        let stacked = landscape.withoutDockedInstrumentEditor

        XCTAssertFalse(stacked.docksInstrumentEditor)
        XCTAssertTrue(stacked.presentsInstrumentAsPopover)
    }

    func testReviewRequestOnlyFiresForACompletedShare() {
        XCTAssertTrue(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .completed))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .canceled))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .failed))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: false, outcome: .completed))
    }

    /// A canceled or failed share must not spend the milestone: the user
    /// keeps their eligibility for the next share that actually completes.
    func testCancelingOrFailingAShareLeavesTheMilestoneUnadvanced() {
        let canceled = ReviewPromptPolicy.afterShareDismiss(
            eligible: true, outcome: .canceled, successfulExports: 5, lastRequestExportCount: 0)
        XCTAssertFalse(canceled.shouldRequestReview)
        XCTAssertEqual(canceled.lastRequestExportCount, 0, "a canceled share must not spend the milestone")

        let failed = ReviewPromptPolicy.afterShareDismiss(
            eligible: true, outcome: .failed, successfulExports: 5, lastRequestExportCount: 0)
        XCTAssertFalse(failed.shouldRequestReview)
        XCTAssertEqual(failed.lastRequestExportCount, 0, "a failed share must not spend the milestone")

        let completed = ReviewPromptPolicy.afterShareDismiss(
            eligible: true, outcome: .completed, successfulExports: 5, lastRequestExportCount: 0)
        XCTAssertTrue(completed.shouldRequestReview)
        XCTAssertEqual(completed.lastRequestExportCount, 5, "a completed share spends the milestone")

        let ineligible = ReviewPromptPolicy.afterShareDismiss(
            eligible: false, outcome: .completed, successfulExports: 5, lastRequestExportCount: 2)
        XCTAssertFalse(ineligible.shouldRequestReview)
        XCTAssertEqual(ineligible.lastRequestExportCount, 2, "not due at all, so nothing to advance")
    }

    func testReviewRequestRetriesAtALaterExportMilestone() {
        XCTAssertFalse(ReviewPromptPolicy.isDue(successfulExports: 2,
                                                lastRequestExportCount: 0))
        XCTAssertTrue(ReviewPromptPolicy.isDue(successfulExports: 3,
                                               lastRequestExportCount: 0))
        XCTAssertFalse(ReviewPromptPolicy.isDue(successfulExports: 12,
                                                lastRequestExportCount: 3))
        XCTAssertTrue(ReviewPromptPolicy.isDue(successfulExports: 13,
                                               lastRequestExportCount: 3))
    }

    func testCapacityWarningAnnouncesOnlyOnThresholdCrossing() {
        XCTAssertTrue(ArrangementCapacityAnnouncement.shouldAnnounce(
            previouslyExceeded: false, nowExceeds: true
        ))
        XCTAssertFalse(ArrangementCapacityAnnouncement.shouldAnnounce(
            previouslyExceeded: true, nowExceeds: true
        ))
        XCTAssertFalse(ArrangementCapacityAnnouncement.shouldAnnounce(
            previouslyExceeded: true, nowExceeds: false
        ))
    }

    // MARK: Export sheet accessibility

    /// The pure mapping VoiceOver's increment/decrement drives, extracted so
    /// it can be tested without a live accessibility tree. This does not
    /// prove the picker is wired up — see the simulator accessibility-tree
    /// check for that.
    func testTailModeAdjustedMapping() {
        XCTAssertEqual(ExportOptions.TailMode.seamlessLoop.adjusted(.increment), .ringOut)
        XCTAssertEqual(ExportOptions.TailMode.ringOut.adjusted(.decrement), .seamlessLoop)
        XCTAssertEqual(ExportOptions.TailMode.ringOut.adjusted(.increment), .ringOut,
                       "already at the far end, increment should not wrap")
        XCTAssertEqual(ExportOptions.TailMode.seamlessLoop.adjusted(.decrement), .seamlessLoop,
                       "already at the near end, decrement should not wrap")
    }

    /// The UIKit node itself: a real accessibility element with the adjustable
    /// trait, whose increment/decrement calls forward to the closure it was
    /// configured with.
    func testAdjustableViewIsAnAdjustableAccessibilityElementThatForwardsToItsClosure() {
        let view = AccessibilityAdjustableControl.AdjustableView()
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityTraits, .adjustable)

        var seen: [AccessibilityAdjustmentDirection] = []
        view.adjust = { seen.append($0) }

        view.accessibilityIncrement()
        view.accessibilityDecrement()

        XCTAssertEqual(seen, [.increment, .decrement])
    }

    // MARK: Keyboard geometry

    /// Two octaves' worth of black keys as KeyboardView lays them out: the
    /// index of the white key each one sits after, the one-octave table
    /// repeated seven white keys up for the second octave.
    private var twoOctaveBlackKeyAfterIndices: [Int] {
        var indices: [Int] = []
        for octave in 0..<2 {
            indices += [0, 1, 3, 4, 5].map { $0 + 7 * octave }
        }
        return indices
    }

    /// The column helper and the view have to agree on how wide a white key
    /// is, or the keys the 44pt test measures are not the keys being drawn.
    /// The view starts from the width inside the keyboard's own padding, which
    /// is the only difference between the two entry points.
    func testKeyboardGeometryWhiteWidthMatchesTheColumnHelper() {
        let columns: [(width: CGFloat, octaves: Int)] = [
            (ChipLayout.sideKeyboardWidth, 1),
            (ChipLayout.wideSideKeyboardWidth, 2)
        ]
        for column in columns {
            let inset = column.width - 2 * ChipLayout.keyboardHorizontalPadding
            let geometry = ChipLayout.KeyboardGeometry(insetWidth: inset,
                                                       whiteKeys: 7 * column.octaves + 1)
            XCTAssertEqual(geometry.whiteWidth,
                           ChipLayout.whiteKeyWidth(columnWidth: column.width,
                                                    octaves: column.octaves),
                           accuracy: 0.001,
                           "\(column.octaves)-octave column disagrees with the view")
        }
    }

    /// A black key belongs over the seam between the two white keys it sits
    /// between, which means the center of the gap — the gap's own width
    /// included. Dividing the width by the key count instead ignores the
    /// fourteen 2pt gaps, and the error compounds along the keyboard.
    func testEveryBlackKeyIsCenteredOnTheGapBetweenItsWhiteNeighbors() {
        let whiteKeys = 15 // two octaves plus the closing C
        let inset = ChipLayout.wideSideKeyboardWidth - 2 * ChipLayout.keyboardHorizontalPadding
        let geometry = ChipLayout.KeyboardGeometry(insetWidth: inset, whiteKeys: whiteKeys)
        let spacing = ChipLayout.whiteKeySpacing

        for after in twoOctaveBlackKeyAfterIndices {
            let gapCenter = CGFloat(after + 1) * (geometry.whiteWidth + spacing) - spacing / 2
            XCTAssertEqual(geometry.blackKeyOffset(after: after) + geometry.blackWidth / 2,
                           gapCenter,
                           accuracy: 0.001,
                           "black key after white key \(after) is off its seam")
        }

        // Why this test exists: the formula it replaces drifts, and by the top
        // of a two-octave keyboard it misses the seam by more than a point.
        let topAfter = twoOctaveBlackKeyAfterIndices.last!
        let naiveWhiteWidth = inset / CGFloat(whiteKeys)
        let naiveCenter = naiveWhiteWidth * CGFloat(topAfter + 1)
            - naiveWhiteWidth * 0.29
            + geometry.blackWidth / 2
        let trueCenter = CGFloat(topAfter + 1) * (geometry.whiteWidth + spacing) - spacing / 2
        XCTAssertGreaterThan(abs(naiveCenter - trueCenter), 1,
                             "the spacing-blind formula should visibly drift by the top key")
    }

    /// The top black key sits between the last two white keys, so it has to
    /// finish inside the keyboard rather than hanging off its right edge.
    func testTheTopBlackKeyStaysInsideTheKeyboard() {
        let inset = ChipLayout.wideSideKeyboardWidth - 2 * ChipLayout.keyboardHorizontalPadding
        let geometry = ChipLayout.KeyboardGeometry(insetWidth: inset, whiteKeys: 15)
        let topAfter = twoOctaveBlackKeyAfterIndices.last!
        XCTAssertLessThanOrEqual(geometry.blackKeyOffset(after: topAfter) + geometry.blackWidth,
                                 inset,
                                 "the top black key overhangs the keyboard")
    }

    // MARK: Book pose (a fold down the middle of the window)

    /// An iPhone Duo's inner display in landscape, status bar on the trailing
    /// edge, as ContentView's GeometryReader measures it: under the side
    /// threshold, so without the fold it stacks and scrolls.
    private let duoInner = CGSize(width: 867, height: 635)
    /// The same display rotated the other way, which today splits at the
    /// 400pt column and runs the fold through the grid.
    private let duoInnerFlipped = CGSize(width: 951, height: 553)
    /// The display in portrait, where the fold runs across instead of down.
    private let duoInnerPortrait = CGSize(width: 669, height: 835)
    /// The division region the simulator reports in both landscape
    /// orientations, flat or partly folded, in the GeometryReader's space.
    private let duoFold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    /// The portrait one: a horizontal strip.
    private let duoPortraitFold = CGRect(x: 0, y: 373.5, width: 669, height: 40)

    /// Passing no fold has to be the two-argument rule exactly, field for
    /// field, or every device without a hinge would move.
    func testNoFoldIsTodaysLayout() {
        let cases: [(CGSize, UserInterfaceSizeClass?)] = [
            (padPortrait, .regular), (padLandscape, .regular),
            (phonePortrait, .compact), (padLandscape, nil)
        ]
        for (size, sizeClass) in cases {
            XCTAssertEqual(ChipLayout.resolve(size: size, horizontalSizeClass: sizeClass, fold: nil),
                           ChipLayout.resolve(size: size, horizontalSizeClass: sizeClass),
                           "\(size) \(String(describing: sizeClass))")
        }
    }

    /// The case the fold exists for: the grid takes the leading half up to
    /// the hinge, the hinge is the gap, and the keys and the docked sound
    /// controls take the trailing half — without scrolling.
    func testDuoInnerLandscapeSplitsAtTheFold() {
        let layout = ChipLayout.resolve(size: duoInner, horizontalSizeClass: .regular,
                                        fold: duoFold)
        XCTAssertTrue(layout.usesSideKeyboard)
        XCTAssertFalse(layout.scrollsEditor)
        XCTAssertTrue(layout.isRegularWidth)
        XCTAssertEqual(layout.sideColumnWidth, 371.5)
        XCTAssertEqual(layout.sideGapWidth, 40)
        XCTAssertEqual(layout.keyboardOctaves, 1)
        XCTAssertEqual(layout.keyboardHeight, 220)
        XCTAssertEqual(layout.keyboardMaxWidth, .infinity)

        let grid = duoInner.width - layout.sideGapWidth - layout.sideColumnWidth
        XCTAssertEqual(grid, 455.5)
        let column = layout.gridColumnWidth(available: grid, tracks: 4, canAddTrack: true)
        XCTAssertLessThanOrEqual(layout.gridRowWidth(columnWidth: column, tracks: 4,
                                                     canAddTrack: true),
                                 grid, "four starter tracks scroll sideways beside the fold")
        XCTAssertGreaterThanOrEqual(layout.gridMinColumnWidth, ChipLayout.phone.gridMinColumnWidth)
        XCTAssertLessThanOrEqual(layout.gridMinColumnWidth, ChipLayout.pad.gridMinColumnWidth)
        XCTAssertEqual(layout.transportForm(width: grid), .row)
    }

    /// Rotated the other way the window is wider, and the fold still decides:
    /// two equal halves rather than a 400pt column with the hinge in the grid.
    func testDuoInnerFlippedSplitsAtTheFoldToo() {
        let layout = ChipLayout.resolve(size: duoInnerFlipped, horizontalSizeClass: .regular,
                                        fold: duoFold)
        XCTAssertTrue(layout.usesSideKeyboard)
        XCTAssertFalse(layout.scrollsEditor)
        XCTAssertEqual(layout.sideColumnWidth, 455.5)
        XCTAssertEqual(layout.sideGapWidth, 40)
        XCTAssertEqual(duoInnerFlipped.width - layout.sideGapWidth - layout.sideColumnWidth, 455.5)
    }

    /// Why the fold matters: the same window without one is under the side
    /// threshold, stacks, and is too short for the stacked keys, so the
    /// keyboard scrolls off the bottom.
    func testDuoInnerWithoutTheFoldScrolls() {
        let layout = ChipLayout.resolve(size: duoInner, horizontalSizeClass: .regular)
        XCTAssertTrue(layout.scrollsEditor)
        XCTAssertFalse(layout.usesSideKeyboard)
    }

    /// Portrait tabletop is left alone: a fold across the window changes
    /// nothing.
    func testHorizontalFoldIsIgnored() {
        XCTAssertEqual(ChipLayout.resolve(size: duoInnerPortrait, horizontalSizeClass: .regular,
                                          fold: duoPortraitFold),
                       ChipLayout.resolve(size: duoInnerPortrait, horizontalSizeClass: .regular))
    }

    /// Compact width, or no size class yet, is the phone whatever the fold.
    func testCompactWidthIgnoresTheFold() {
        XCTAssertEqual(ChipLayout.resolve(size: duoInner, horizontalSizeClass: .compact,
                                          fold: duoFold), .phone)
        XCTAssertEqual(ChipLayout.resolve(size: duoInner, horizontalSizeClass: nil,
                                          fold: duoFold), .phone)
    }

    /// A fold that leaves either side under its minimum isn't worth
    /// splitting at, and one outside the window isn't this window's.
    func testAFoldTooFarToOneSideIsIgnored() {
        let folds = [
            CGRect(x: 700, y: 0, width: 40, height: 669),   // keys too narrow
            CGRect(x: 200, y: 0, width: 40, height: 669),   // grid too narrow
            CGRect(x: 1200, y: 0, width: 40, height: 669),  // past the trailing edge
            CGRect(x: -100, y: 0, width: 40, height: 669)   // before the leading edge
        ]
        let unfolded = ChipLayout.resolve(size: duoInner, horizontalSizeClass: .regular)
        for fold in folds {
            XCTAssertEqual(ChipLayout.resolve(size: duoInner, horizontalSizeClass: .regular,
                                              fold: fold),
                           unfolded, "\(fold)")
        }
    }

    /// The minimums are what they claim: the narrowest grid side holds four
    /// tracks at the phone's column floor, and the narrowest key side draws
    /// eight 40pt white keys.
    func testFoldMinimumsMatchWhatTheyHold() {
        var floorLayout = ChipLayout.pad
        floorLayout.gridMinColumnWidth = ChipLayout.phone.gridMinColumnWidth
        XCTAssertEqual(floorLayout.gridRowWidth(columnWidth: ChipLayout.phone.gridMinColumnWidth,
                                                tracks: 4, canAddTrack: true),
                       ChipLayout.minimumFoldGridWidth)
        XCTAssertEqual(ChipLayout.whiteKeyWidth(columnWidth: ChipLayout.minimumFoldColumnWidth,
                                                octaves: 1), 40)
    }

    /// The 371.5pt column the 867pt window leaves still draws keys a finger
    /// can find.
    func testWhiteKeysInTheFoldColumnAreAtLeast40pt() {
        XCTAssertGreaterThanOrEqual(ChipLayout.whiteKeyWidth(columnWidth: 371.5, octaves: 1), 40)
    }
}
