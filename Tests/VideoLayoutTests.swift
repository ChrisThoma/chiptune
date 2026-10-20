import XCTest
@testable import Chiptune

/// Frame geometry for both video styles. Reels, TikTok and Shorts lay their
/// own buttons and captions over the top and bottom of a 9:16 video, so
/// everything that carries meaning has to sit between those bands.
final class VideoLayoutTests: XCTestCase {

    private let frame = CGRect(x: 0, y: 0, width: 1080, height: 1920)

    func testTheFrameIsPortrait1080By1920() {
        XCTAssertEqual(VideoLayout.size, CGSize(width: 1080, height: 1920))
    }

    func testTheSafeAreaClearsTheOverlayBands() {
        let safe = VideoLayout.safeRect
        XCTAssertTrue(frame.contains(safe))
        XCTAssertGreaterThanOrEqual(safe.minY, 1920 * 0.12)
        XCTAssertLessThanOrEqual(safe.maxY, 1920 - Self.captionReach)
    }

    /// TikTok's caption, account name and sound line can stack up to about
    /// 480px from the bottom of a 1920px frame on a long caption.
    private static let captionReach: CGFloat = 480

    func testTheBottomBandClearsALongTikTokCaption() {
        XCTAssertGreaterThanOrEqual(VideoLayout.bottomBand, Self.captionReach)
        for count in [1, 4, 8] {
            let layout = VideoLayout(trackCount: count)
            for (name, rect) in [("tag", VideoLayout.tagRect), ("grid", layout.gridRect),
                                 ("cartridge", layout.cartridgeRect)] {
                XCTAssertLessThanOrEqual(rect.maxY, 1920 - Self.captionReach, "\(count) / \(name)")
            }
        }
    }

    // MARK: Grid

    func testColumnsFitTheSafeWidthForOneFourAndEightTracks() {
        let safe = VideoLayout.safeRect
        for count in [1, 4, 8] {
            let layout = VideoLayout(trackCount: count)
            XCTAssertGreaterThan(layout.columnWidth, 0, "\(count)")
            XCTAssertGreaterThanOrEqual(layout.gutterRect(centerY: 900).minX, safe.minX, "\(count)")
            var previous: CGRect?
            for track in 0..<count {
                let cell = layout.cellRect(track: track, centerY: 900)
                XCTAssertGreaterThanOrEqual(cell.minX, safe.minX, "\(count) / \(track)")
                XCTAssertLessThanOrEqual(cell.maxX, safe.maxX, "\(count) / \(track)")
                if let previous { XCTAssertLessThan(previous.maxX, cell.minX, "\(count) / \(track) overlaps") }
                previous = cell
            }
        }
    }

    /// A lone track shouldn't stretch into one huge bar.
    func testASingleColumnIsCapped() {
        XCTAssertLessThan(VideoLayout(trackCount: 1).columnWidth, VideoLayout.safeRect.width / 2)
    }

    func testEightColumnsLeaveRoomForANoteName() {
        XCTAssertGreaterThanOrEqual(VideoLayout(trackCount: 8).columnWidth, 70)
    }

    /// The step that is playing always sits on the same row; the grid moves
    /// under it.
    func testThePlayingStepIsAlwaysOnThePlayheadRow() {
        for count in [1, 4, 8] {
            let layout = VideoLayout(trackCount: count)
            for step in [0, 7, 63] {
                XCTAssertEqual(layout.rowCenterY(step: step, position: Double(step)), layout.playheadY)
            }
            XCTAssertEqual(layout.rowCenterY(step: 4, position: 3.5), layout.playheadY + layout.rowPitch / 2)
        }
        let grid = VideoLayout(trackCount: 4).gridRect
        XCTAssertEqual(VideoLayout(trackCount: 4).playheadY, grid.midY, accuracy: 0.5)
    }

    func testTheVisibleWindowClampsAtThePatternsEnds() {
        let layout = VideoLayout(trackCount: 4)
        XCTAssertEqual(layout.visibleSteps(position: 0, patternLength: 16).lowerBound, 0)
        XCTAssertEqual(layout.visibleSteps(position: 15, patternLength: 16).upperBound, 15)
        let middle = layout.visibleSteps(position: 32, patternLength: 64)
        XCTAssertGreaterThan(middle.lowerBound, 0)
        XCTAssertLessThan(middle.upperBound, 63)
        XCTAssertTrue(middle.contains(32))
    }

    /// Every row in the window at least touches the grid area, and the rows
    /// just outside it don't, so nothing visible is skipped.
    func testTheWindowCoversTheGridAreaAndNoMore() {
        let layout = VideoLayout(trackCount: 4)
        let window = layout.visibleSteps(position: 32, patternLength: 64)
        let grid = layout.gridRect
        for step in [window.lowerBound, window.upperBound] {
            let y = layout.rowCenterY(step: step, position: 32)
            XCTAssertLessThan(y - layout.cellHeight / 2, grid.maxY, "\(step)")
            XCTAssertGreaterThan(y + layout.cellHeight / 2, grid.minY, "\(step)")
        }
        for step in [window.lowerBound - 2, window.upperBound + 2] {
            let y = layout.rowCenterY(step: step, position: 32)
            XCTAssertTrue(y + layout.cellHeight / 2 <= grid.minY || y - layout.cellHeight / 2 >= grid.maxY, "\(step)")
        }
    }

    /// Between steps the grid has scrolled part of a row, so the window
    /// follows the fraction: the row coming up from below appears before its
    /// step starts.
    func testTheWindowFollowsAScrollBetweenSteps() {
        let layout = VideoLayout(trackCount: 4)
        let grid = layout.gridRect
        for position in [32.25, 32.5, 32.95] {
            let window = layout.visibleSteps(position: position, patternLength: 64)
            for step in [window.lowerBound, window.upperBound] {
                let y = layout.rowCenterY(step: step, position: position)
                XCTAssertLessThan(y - layout.cellHeight / 2, grid.maxY, "\(position) / \(step)")
                XCTAssertGreaterThan(y + layout.cellHeight / 2, grid.minY, "\(position) / \(step)")
            }
            let below = layout.rowCenterY(step: window.upperBound + 1, position: position)
            XCTAssertGreaterThanOrEqual(below - layout.cellHeight / 2, grid.maxY, "\(position)")
        }
    }

    func testTheGridSitsInsideTheSafeArea() {
        let safe = VideoLayout.safeRect
        let layout = VideoLayout(trackCount: 8)
        XCTAssertTrue(safe.contains(layout.gridRect))
        XCTAssertTrue(safe.contains(layout.headerRect))
        XCTAssertLessThanOrEqual(layout.headerRect.maxY, layout.columnHeaderY - layout.columnHeaderHeight / 2)
        XCTAssertLessThanOrEqual(layout.columnHeaderY + layout.columnHeaderHeight / 2, layout.gridRect.minY)
    }

    // MARK: Cartridge

    /// A tall cartridge, centred, with room left round it for its shadow.
    func testTheCartridgeSitsInsideTheSafeArea() {
        for count in [1, 4, 8] {
            let cart = VideoLayout(trackCount: count).cartridgeRect
            XCTAssertTrue(VideoLayout.safeRect.contains(cart), "\(count)")
            XCTAssertGreaterThan(cart.height, cart.width, "\(count)")
            XCTAssertEqual(cart.midX, VideoLayout.safeRect.midX, accuracy: 0.5)
        }
    }

    /// The outline runs clockwise from the top-left corner; its second and
    /// third points are the ends of the diagonal cut off the top-right
    /// corner, which stays above the label.
    func testTheNotchIsCutFromTheTopRightCorner() {
        let layout = VideoLayout(trackCount: 4)
        let cart = layout.cartridgeRect
        let outline = layout.cartridgeOutline
        // Compared whole, so a short outline fails here instead of crashing
        // the test process on an out-of-range index.
        XCTAssertEqual(outline, [
            CGPoint(x: cart.minX, y: cart.minY),
            CGPoint(x: cart.maxX - layout.cartridgeNotch, y: cart.minY),
            CGPoint(x: cart.maxX, y: cart.minY + layout.cartridgeNotch),
            CGPoint(x: cart.maxX, y: cart.maxY),
            CGPoint(x: cart.minX, y: cart.maxY),
        ])
        XCTAssertGreaterThan(layout.cartridgeNotch, layout.cartridgeCornerRadius)
        XCTAssertGreaterThan(cart.maxX - layout.cartridgeNotch, cart.midX)
        XCTAssertLessThan(cart.minY + layout.cartridgeNotch, layout.labelRecessRect.minY)
    }

    /// Grip ridges stack across the band above the label, inside the body
    /// and clear of the notch's diagonal.
    func testGripRidgesRunAcrossTheTopBand() {
        let layout = VideoLayout(trackCount: 4)
        let cart = layout.cartridgeRect
        let ridges = layout.gripRidgeRects
        XCTAssertGreaterThanOrEqual(ridges.count, 4)
        var previous: CGRect?
        for (index, ridge) in ridges.enumerated() {
            XCTAssertTrue(cart.contains(ridge), "\(index)")
            XCTAssertGreaterThan(ridge.minY, cart.minY, "\(index)")
            XCTAssertLessThan(ridge.maxY, layout.labelRecessRect.minY, "\(index)")
            XCTAssertGreaterThan(ridge.width, cart.width / 2, "\(index)")
            // The top-right corner is inside the body, not in the cut.
            XCTAssertLessThanOrEqual(ridge.maxX - (cart.maxX - layout.cartridgeNotch), ridge.minY - cart.minY, "\(index)")
            if let previous { XCTAssertLessThan(previous.maxY, ridge.minY, "\(index)") }
            previous = ridge
        }
    }

    /// The label sits in a recess that takes most of the body, with a bevel
    /// of plastic all round it.
    func testTheLabelIsInsetInsideTheBody() {
        let layout = VideoLayout(trackCount: 4)
        let cart = layout.cartridgeRect
        let recess = layout.labelRecessRect
        let label = layout.labelRect
        XCTAssertTrue(cart.insetBy(dx: 24, dy: 24).contains(recess))
        XCTAssertTrue(recess.insetBy(dx: 8, dy: 8).contains(label))
        XCTAssertGreaterThan(label.width * label.height, cart.width * cart.height / 2)
    }

    func testTheTitleBarsAndProgressSitInsideTheLabel() {
        for count in [1, 4, 8] {
            let layout = VideoLayout(trackCount: count)
            let label = layout.labelRect
            for (name, rect) in [("title", layout.coverTitleRect), ("meta", layout.coverMetaRect),
                                 ("progress", layout.coverProgressRect), ("times", layout.coverTimeRect)] {
                XCTAssertTrue(label.contains(rect), "\(count) / \(name)")
            }
            var previous: CGRect?
            for track in 0..<count {
                let bar = layout.coverBarRect(track: track)
                XCTAssertTrue(label.contains(bar), "\(count) / \(track)")
                XCTAssertGreaterThan(bar.height, 200)
                XCTAssertGreaterThanOrEqual(bar.width, 40)
                if let previous { XCTAssertLessThan(previous.maxX, bar.minX) }
                previous = bar
            }
            XCTAssertLessThan(layout.coverMetaRect.maxY, layout.coverBarRect(track: 0).minY)
            XCTAssertLessThan(layout.coverBarRect(track: 0).maxY, layout.coverBarLabelY - 20)
            XCTAssertLessThan(layout.coverBarLabelY + 20, layout.coverProgressRect.minY)
        }
    }

    /// The moulded arrow sits in the plastic under the label.
    func testTheTriangleSitsBetweenTheLabelAndTheBodysBottom() {
        let layout = VideoLayout(trackCount: 4)
        let triangle = layout.triangleRect
        XCTAssertGreaterThan(triangle.minY, layout.labelRecessRect.maxY)
        XCTAssertLessThan(triangle.maxY, layout.cartridgeRect.maxY)
        XCTAssertEqual(triangle.midX, layout.cartridgeRect.midX, accuracy: 0.5)
        XCTAssertGreaterThan(triangle.width, 0)
        XCTAssertGreaterThan(triangle.height, 0)
    }

    /// The numbers Android's VideoLayoutTest pins too, so both platforms
    /// draw the same cartridge.
    func testTheCartridgeGeometryIsPinned() {
        let layout = VideoLayout(trackCount: 4)
        XCTAssertEqual(layout.cartridgeRect, CGRect(x: 150, y: 252, width: 780, height: 1100))
        XCTAssertEqual(layout.cartridgeNotch, 96)
        XCTAssertEqual(layout.cartridgeCornerRadius, 28)
        XCTAssertEqual(layout.gripRidgeRects.count, 5)
        XCTAssertEqual(layout.gripRidgeRects.first, CGRect(x: 214, y: 286, width: 580, height: 8))
        XCTAssertEqual(layout.labelRecessRect, CGRect(x: 202, y: 402, width: 676, height: 774))
        XCTAssertEqual(layout.labelRect, CGRect(x: 216, y: 416, width: 648, height: 746))
        XCTAssertEqual(layout.triangleRect, CGRect(x: 508, y: 1236, width: 64, height: 56))
        XCTAssertEqual(layout.coverTitleRect, CGRect(x: 256, y: 456, width: 568, height: 190))
        XCTAssertEqual(layout.coverProgressRect, CGRect(x: 256, y: 1062, width: 568, height: 14))
        XCTAssertEqual(layout.coverBarRect(track: 0), CGRect(x: 256, y: 752, width: 124, height: 220))
        XCTAssertEqual(VideoLayout(trackCount: 8).coverBarRect(track: 7), CGRect(x: 774, y: 752, width: 50, height: 220))
    }

    // MARK: Track names

    /// Width of `text` as the renderer draws it: SF Mono, bold.
    private func width(_ text: String, size: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: size, weight: .bold)]).width
    }

    /// Track names side by side: each within its own slot, none touching the
    /// next, a default name ("PU1 A") whole at the size drawn, and more space
    /// between two names than the space inside one, so "PU1 A PU2 A" reads as
    /// two names rather than one run.
    private func assertNamesStaySeparate(_ rects: [CGRect], centres: [CGFloat], size: CGFloat,
                                         _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let name = width("PU1 A", size: size)
        let space = width(" ", size: size)
        for (index, rect) in rects.enumerated() {
            XCTAssertEqual(rect.midX, centres[index], accuracy: 0.5, "\(what) / \(index) centred", file: file, line: line)
            XCTAssertLessThanOrEqual(name, rect.width, "\(what) / \(index) truncates a default name", file: file, line: line)
            guard index > 0 else { continue }
            XCTAssertLessThanOrEqual(rects[index - 1].maxX, rect.minX, "\(what) / \(index) overlaps", file: file, line: line)
            let textGap = (centres[index] - name / 2) - (centres[index - 1] + name / 2)
            XCTAssertGreaterThan(textGap, 1.5 * space, "\(what) / \(index) runs into the one before", file: file, line: line)
        }
    }

    func testCartridgeTrackNamesStaySeparateForOneToEightTracks() {
        for count in 1...8 {
            let layout = VideoLayout(trackCount: count)
            let rects = (0..<count).map { layout.coverBarLabelRect(track: $0) }
            let centres = (0..<count).map { layout.coverBarRect(track: $0).midX }
            assertNamesStaySeparate(rects, centres: centres, size: layout.coverLabelFontSize, "cartridge \(count)")
            for rect in rects { XCTAssertTrue(layout.labelRect.contains(rect), "\(count)") }
        }
    }

    func testGridColumnNamesStaySeparateForOneToEightTracks() {
        for count in 1...8 {
            let layout = VideoLayout(trackCount: count)
            let rects = (0..<count).map { layout.columnHeaderRect(track: $0) }
            let centres = (0..<count).map { layout.cellRect(track: $0, centerY: 900).midX }
            assertNamesStaySeparate(rects, centres: centres, size: layout.columnHeaderFontSize, "grid \(count)")
            for rect in rects { XCTAssertTrue(VideoLayout.safeRect.contains(rect), "\(count)") }
        }
    }

    /// Few tracks keep the full-size names; only crowded rows shrink them.
    func testNamesOnlyShrinkWhenCrowded() {
        XCTAssertEqual(VideoLayout(trackCount: 4).coverLabelFontSize, 26)
        XCTAssertEqual(VideoLayout(trackCount: 4).columnHeaderFontSize, 26)
        XCTAssertLessThan(VideoLayout(trackCount: 8).coverLabelFontSize, 26)
        XCTAssertLessThan(VideoLayout(trackCount: 8).columnHeaderFontSize, 26)
    }

    // MARK: Tag

    func testTheTagIsInsideTheFrameAndClearOfTheBottomOverlays() {
        let tag = VideoLayout.tagRect
        XCTAssertTrue(frame.contains(tag))
        XCTAssertLessThanOrEqual(tag.maxY, 1920 - Self.captionReach)
        XCTAssertGreaterThanOrEqual(tag.minY, 1920 * 0.12)
        XCTAssertGreaterThanOrEqual(tag.minX, VideoLayout.safeRect.minX)
        XCTAssertLessThanOrEqual(tag.maxY, VideoLayout.size.height - VideoLayout.bottomBand)
    }

    /// "Made with Chiptune" sits under the cartridge, not on it.
    func testTheTagSitsBelowTheCartridge() {
        for count in [1, 4, 8] {
            XCTAssertGreaterThan(VideoLayout.tagRect.minY, VideoLayout(trackCount: count).cartridgeRect.maxY)
        }
    }

    func testTheTagOverlapsNeitherStylesContent() {
        let layout = VideoLayout(trackCount: 8)
        XCTAssertFalse(VideoLayout.tagRect.intersects(layout.gridRect))
        XCTAssertFalse(VideoLayout.tagRect.intersects(layout.cartridgeRect))
    }
}
