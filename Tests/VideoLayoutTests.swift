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
        XCTAssertLessThanOrEqual(safe.maxY, 1920 * 0.80)
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

    // MARK: Cover

    func testCoverBarsSitSideBySideInsideTheCard() {
        for count in [1, 4, 8] {
            let layout = VideoLayout(trackCount: count)
            XCTAssertTrue(VideoLayout.safeRect.contains(layout.coverCardRect))
            var previous: CGRect?
            for track in 0..<count {
                let bar = layout.coverBarRect(track: track)
                XCTAssertTrue(layout.coverCardRect.contains(bar), "\(count) / \(track)")
                XCTAssertGreaterThan(bar.height, 200)
                if let previous { XCTAssertLessThan(previous.maxX, bar.minX) }
                previous = bar
            }
            XCTAssertTrue(layout.coverCardRect.contains(layout.coverProgressRect))
            XCTAssertLessThan(layout.coverTitleRect.maxY, layout.coverBarRect(track: 0).minY)
            XCTAssertLessThan(layout.coverBarRect(track: 0).maxY, layout.coverProgressRect.minY)
        }
    }

    // MARK: Tag

    func testTheTagIsInsideTheFrameAndClearOfTheBottomOverlays() {
        let tag = VideoLayout.tagRect
        XCTAssertTrue(frame.contains(tag))
        XCTAssertLessThanOrEqual(tag.maxY, 1920 * 0.80)
        XCTAssertGreaterThanOrEqual(tag.minY, 1920 * 0.12)
        XCTAssertGreaterThanOrEqual(tag.minX, VideoLayout.safeRect.minX)
    }

    func testTheTagOverlapsNeitherStylesContent() {
        let layout = VideoLayout(trackCount: 8)
        XCTAssertFalse(VideoLayout.tagRect.intersects(layout.gridRect))
        XCTAssertFalse(VideoLayout.tagRect.intersects(layout.coverCardRect))
    }
}
