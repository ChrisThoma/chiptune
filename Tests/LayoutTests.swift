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
            let layout = ChipLayout.resolve(size: CGSize(width: width, height: 500),
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

    func testChromeStopsSpreadingOnIPadAndNeverDoesOnIPhone() {
        let pad = ChipLayout.resolve(size: padLandscape, horizontalSizeClass: .regular)
        XCTAssertLessThan(pad.chromeMaxWidth,
                          padLandscape.width - ChipLayout.sideKeyboardWidth,
                          "Capped wider than the grid column is no cap at all")
        XCTAssertEqual(ChipLayout.phone.chromeMaxWidth, .infinity)
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
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .cancelled))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: true, outcome: .failed))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequest(eligible: false, outcome: .completed))
    }

    /// A cancelled or failed share must not spend the milestone: the user
    /// keeps their eligibility for the next share that actually completes.
    func testCancellingOrFailingAShareLeavesTheMilestoneUnadvanced() {
        let cancelled = ReviewPromptPolicy.afterShareDismiss(
            eligible: true, outcome: .cancelled, successfulExports: 5, lastRequestExportCount: 0)
        XCTAssertFalse(cancelled.shouldRequestReview)
        XCTAssertEqual(cancelled.lastRequestExportCount, 0, "a cancelled share must not spend the milestone")

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
    /// between, which means the centre of the gap — the gap's own width
    /// included. Dividing the width by the key count instead ignores the
    /// fourteen 2pt gaps, and the error compounds along the keyboard.
    func testEveryBlackKeyIsCentredOnTheGapBetweenItsWhiteNeighbours() {
        let whiteKeys = 15 // two octaves plus the closing C
        let inset = ChipLayout.wideSideKeyboardWidth - 2 * ChipLayout.keyboardHorizontalPadding
        let geometry = ChipLayout.KeyboardGeometry(insetWidth: inset, whiteKeys: whiteKeys)
        let spacing = ChipLayout.whiteKeySpacing

        for after in twoOctaveBlackKeyAfterIndices {
            let gapCentre = CGFloat(after + 1) * (geometry.whiteWidth + spacing) - spacing / 2
            XCTAssertEqual(geometry.blackKeyOffset(after: after) + geometry.blackWidth / 2,
                           gapCentre,
                           accuracy: 0.001,
                           "black key after white key \(after) is off its seam")
        }

        // Why this test exists: the formula it replaces drifts, and by the top
        // of a two-octave keyboard it misses the seam by more than a point.
        let topAfter = twoOctaveBlackKeyAfterIndices.last!
        let naiveWhiteWidth = inset / CGFloat(whiteKeys)
        let naiveCentre = naiveWhiteWidth * CGFloat(topAfter + 1)
            - naiveWhiteWidth * 0.29
            + geometry.blackWidth / 2
        let trueCentre = CGFloat(topAfter + 1) * (geometry.whiteWidth + spacing) - spacing / 2
        XCTAssertGreaterThan(abs(naiveCentre - trueCentre), 1,
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
}
