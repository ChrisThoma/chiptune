import CoreGraphics

/// The geometry for dragging a track header sideways in the grid's reorder
/// mode. Kept out of the view so the thresholds can be tested without a
/// gesture: `destination` feeds `Studio.moveTrack(from:to:)` on drop, and
/// `offset` slides the other columns aside while the drag is live.
enum TrackReorder {
    /// The column a header dragged `translation` points from `source` has
    /// reached. Rounds, so a column swaps once the dragged one is more than
    /// halfway over it, and clamps, so an overshoot lands at the end.
    static func destination(from source: Int, translation: CGFloat,
                            columnStep: CGFloat, count: Int) -> Int {
        guard columnStep > 0, count > 0 else { return source }
        let columns = Int((translation / columnStep).rounded())
        return min(max(source + columns, 0), count - 1)
    }

    /// How far column `index` slides to make room while `dragged` hovers over
    /// `destination`: the columns in between shift one step toward the gap
    /// the dragged column left. The dragged column itself follows the finger,
    /// so it gets nothing here.
    static func offset(for index: Int, dragging dragged: Int, to destination: Int,
                       columnStep: CGFloat) -> CGFloat {
        if dragged < destination, index > dragged, index <= destination { return -columnStep }
        if dragged > destination, index >= destination, index < dragged { return columnStep }
        return 0
    }
}

extension Song {
    /// One track has nowhere to go, so the header long press that enters
    /// reorder mode does nothing.
    var canReorderTracks: Bool { tracks.count > 1 }
}
