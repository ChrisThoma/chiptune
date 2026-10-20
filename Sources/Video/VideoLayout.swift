import CoreGraphics

/// Where everything goes in a 1080×1920 video frame, for both styles. Pure
/// geometry, in pixels with the origin at the top left, so it can be tested
/// without drawing and the Android drawer can follow the same numbers.
///
/// Reels, TikTok and Shorts all lay their own chrome over a 9:16 video: a
/// title or tabs along the top, and the caption, account name and buttons
/// across the bottom fifth, with a column of buttons up the right edge.
/// Anything that carries meaning stays inside `safeRect`; only the
/// background runs to the edges.
struct VideoLayout {
    static let size = CGSize(width: 1080, height: 1920)
    /// Kept clear at the top: 12.5% of the height.
    static let topBand: CGFloat = 240
    /// Kept clear at the bottom: a quarter of the height. TikTok's caption,
    /// account name and sound line reach about 480px up on a long caption.
    static let bottomBand: CGFloat = 480
    /// Wide enough on the right to clear TikTok's button column; the same on
    /// the left so the content stays centred.
    static let sideMargin: CGFloat = 120

    static var safeRect: CGRect {
        CGRect(x: sideMargin, y: topBand,
               width: size.width - 2 * sideMargin,
               height: size.height - topBand - bottomBand)
    }

    /// "Made with Chiptune", in the bottom-left corner of the safe area: low
    /// enough to stay out of the way, high enough to stay above the caption.
    static var tagRect: CGRect {
        CGRect(x: safeRect.minX, y: safeRect.maxY - tagHeight, width: 420, height: tagHeight)
    }
    static let tagHeight: CGFloat = 40
    static let tagFontSize: CGFloat = 28

    /// The bottom of everything but the tag.
    static var contentBottom: CGFloat { tagRect.minY - 24 }

    let trackCount: Int

    init(trackCount: Int) {
        self.trackCount = min(max(trackCount, 1), Chip.maxTracks)
    }

    // MARK: Grid

    /// Song title and the pattern/step readout.
    var headerRect: CGRect {
        CGRect(x: Self.safeRect.minX, y: Self.safeRect.minY, width: Self.safeRect.width, height: 150)
    }
    let titleFontSize: CGFloat = 56
    let subtitleFontSize: CGFloat = 34

    let columnHeaderHeight: CGFloat = 52
    /// Centre line of the track names above the columns.
    var columnHeaderY: CGFloat { headerRect.maxY + 16 + columnHeaderHeight / 2 }
    let columnHeaderFontSize: CGFloat = 26

    /// Where rows are drawn; they are clipped to it as they scroll.
    var gridRect: CGRect {
        let top = columnHeaderY + columnHeaderHeight / 2 + 12
        return CGRect(x: Self.safeRect.minX, y: top,
                      width: Self.safeRect.width, height: Self.contentBottom - top)
    }

    /// The fixed playing row's centre. The grid scrolls under it.
    var playheadY: CGFloat { gridRect.midY }

    let rowPitch: CGFloat = 66
    let cellHeight: CGFloat = 58
    let gutterWidth: CGFloat = 76
    let gap: CGFloat = 10
    /// Theme.cellRadius is 5pt on a cell of about 24pt in the app; this keeps
    /// the same proportion at video size.
    var cellRadius: CGFloat { Theme.cellRadius * cellHeight / 24 }
    /// A single column wider than this reads as a bar, not a grid.
    let maxColumnWidth: CGFloat = 180

    /// Every column is the same width, sized so eight fit the safe area with
    /// the step-number gutter.
    var columnWidth: CGFloat {
        let available = Self.safeRect.width - gutterWidth - gap - gap * CGFloat(trackCount - 1)
        return min(maxColumnWidth, (available / CGFloat(trackCount)).rounded(.down))
    }

    /// Note names shrink with the columns so "C#4" still fits eight across.
    var cellFontSize: CGFloat { min(30, (columnWidth * 0.3).rounded(.down)) }
    let gutterFontSize: CGFloat = 26

    /// Gutter plus columns, centred in the safe area.
    private var gridContentWidth: CGFloat {
        gutterWidth + gap + CGFloat(trackCount) * columnWidth + CGFloat(trackCount - 1) * gap
    }
    private var gridOriginX: CGFloat { Self.safeRect.midX - gridContentWidth / 2 }

    func gutterRect(centerY: CGFloat) -> CGRect {
        CGRect(x: gridOriginX, y: centerY - cellHeight / 2, width: gutterWidth, height: cellHeight)
    }

    func cellRect(track: Int, centerY: CGFloat) -> CGRect {
        let x = gridOriginX + gutterWidth + gap + CGFloat(track) * (columnWidth + gap)
        return CGRect(x: x, y: centerY - cellHeight / 2, width: columnWidth, height: cellHeight)
    }

    /// The highlight behind the playing row, spanning gutter and columns.
    var playheadRowRect: CGRect {
        CGRect(x: gridOriginX - 12, y: playheadY - rowPitch / 2,
               width: gridContentWidth + 24, height: rowPitch)
    }

    /// Where `step`'s row is centred when the song is `position` steps into
    /// the pattern (fraction included). At `position == step` that is the
    /// playhead row, so a note reaches it on the frame its sound starts.
    func rowCenterY(step: Int, position: Double) -> CGFloat {
        playheadY + CGFloat(Double(step) - position) * rowPitch
    }

    /// The steps of a `patternLength`-step pattern with any part of their row
    /// inside `gridRect` at `position`. Only the current pattern is drawn, so
    /// the window stops at its first and last steps rather than showing the
    /// neighbours.
    func visibleSteps(position: Double, patternLength: Int) -> ClosedRange<Int> {
        let reach = Double((gridRect.height / 2 + cellHeight / 2) / rowPitch)
        // Strictly inside: a row whose edge only meets the grid's edge shows
        // nothing.
        let lower = Int((position - reach).rounded(.down)) + 1
        let upper = Int((position + reach).rounded(.up)) - 1
        let last = max(patternLength - 1, 0)
        let lo = min(max(lower, 0), last)
        return lo...max(min(upper, last), lo)
    }

    // MARK: Cartridge (the Cover style)

    /// The cartridge's body: a tall slab of grey plastic, centred, a little
    /// inside the safe area so its shadow has room.
    var cartridgeRect: CGRect {
        let width: CGFloat = 780
        let top = Self.safeRect.minY + 12
        return CGRect(x: Self.safeRect.midX - width / 2, y: top,
                      width: width, height: Self.contentBottom - 24 - top)
    }
    /// The legs of the diagonal cut off the top-right corner.
    let cartridgeNotch: CGFloat = 96
    /// The other three corners are rounded this much.
    let cartridgeCornerRadius: CGFloat = 28

    /// The body's corners, clockwise from the top left, with the notch's two
    /// ends in place of the top-right corner. The renderer rounds the three
    /// square corners by `cartridgeCornerRadius`.
    var cartridgeOutline: [CGPoint] {
        let cart = cartridgeRect
        return [
            CGPoint(x: cart.minX, y: cart.minY),
            CGPoint(x: cart.maxX - cartridgeNotch, y: cart.minY),
            CGPoint(x: cart.maxX, y: cart.minY + cartridgeNotch),
            CGPoint(x: cart.maxX, y: cart.maxY),
            CGPoint(x: cart.minX, y: cart.maxY),
        ]
    }

    /// Grip ridges moulded across the top band, stopping short of the notch.
    var gripRidgeRects: [CGRect] {
        let cart = cartridgeRect
        let left = cart.minX + 64
        let right = cart.maxX - cartridgeNotch - 40
        return (0..<5).map { index in
            CGRect(x: left, y: cart.minY + 34 + CGFloat(index) * 22, width: right - left, height: 8)
        }
    }

    /// The sunken area the label is stuck into. Its rim is the bevel.
    var labelRecessRect: CGRect {
        let cart = cartridgeRect
        return CGRect(x: cart.minX + 52, y: cart.minY + 150,
                      width: cart.width - 104, height: cart.height - 150 - 176)
    }

    /// The label: the app's dark background, carrying the song.
    var labelRect: CGRect { labelRecessRect.insetBy(dx: 14, dy: 14) }

    /// The bounding box of the arrow moulded under the label, pointing up.
    var triangleRect: CGRect {
        let cart = cartridgeRect
        let width: CGFloat = 64, height: CGFloat = 56
        let centerY = (labelRecessRect.maxY + cart.maxY) / 2
        return CGRect(x: cart.midX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    let coverPadding: CGFloat = 40
    let coverTitleFontSize: CGFloat = 72
    let coverMetaFontSize: CGFloat = 34
    let coverLabelFontSize: CGFloat = 26

    /// Up to two lines of title.
    var coverTitleRect: CGRect {
        CGRect(x: labelRect.minX + coverPadding, y: labelRect.minY + coverPadding,
               width: labelRect.width - 2 * coverPadding, height: 190)
    }

    /// Tempo and length.
    var coverMetaRect: CGRect {
        CGRect(x: coverTitleRect.minX, y: coverTitleRect.maxY + 8,
               width: coverTitleRect.width, height: 48)
    }

    var coverProgressRect: CGRect {
        CGRect(x: labelRect.minX + coverPadding, y: labelRect.maxY - 100,
               width: labelRect.width - 2 * coverPadding, height: 14)
    }

    /// Elapsed and total time, under the progress bar.
    var coverTimeRect: CGRect {
        CGRect(x: coverProgressRect.minX, y: coverProgressRect.maxY + 14,
               width: coverProgressRect.width, height: 40)
    }

    private var coverBarGap: CGFloat { 24 }
    private var coverBarsTop: CGFloat { coverMetaRect.maxY + 50 }
    /// Room under the bars for each track's name.
    private var coverBarsBottom: CGFloat { coverProgressRect.minY - 90 }
    private var coverBarWidth: CGFloat {
        let available = labelRect.width - 2 * coverPadding - coverBarGap * CGFloat(trackCount - 1)
        return min(140, (available / CGFloat(trackCount)).rounded(.down))
    }

    /// The full extent of a track's bar. The renderer fills it from the
    /// bottom by the track's pulse.
    func coverBarRect(track: Int) -> CGRect {
        let total = CGFloat(trackCount) * coverBarWidth + CGFloat(trackCount - 1) * coverBarGap
        let x = labelRect.midX - total / 2 + CGFloat(track) * (coverBarWidth + coverBarGap)
        return CGRect(x: x, y: coverBarsTop, width: coverBarWidth, height: coverBarsBottom - coverBarsTop)
    }

    /// Track names sit centred under their bars.
    var coverBarLabelY: CGFloat { coverBarsBottom + 40 }
}
