import Foundation

/// How many repeats a video starts at when the user hasn't picked a count.
enum ExportRepeats {
    /// The song a video should at least show, before its ring-out.
    static let videoBodySeconds = 10.0

    /// The smallest count, up to `ExportOptions.maxLoopCount`, whose passes
    /// (before the tail) run at least `videoBodySeconds`. The starter song
    /// is 1.8 s, so it gets 6.
    static func forVideo(song: Song) -> Int {
        let pass = song.arrangementDuration
        guard pass > 0 else { return 1 }
        // A hair of slack so a pass that divides ten exactly isn't pushed
        // one count further by rounding.
        let needed = Int((videoBodySeconds / pass - 1e-9).rounded(.up))
        return min(max(needed, 1), ExportOptions.maxLoopCount)
    }
}
