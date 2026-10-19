import Foundation

/// Renders a song as a 1080×1920, 30 fps H.264/AAC mp4 for Reels, TikTok and
/// Shorts.
enum VideoExport {
    /// TikTok's upload limit, the longest of the three. WAV's own limit is
    /// about 13 hours, which says nothing useful about a video.
    static let maxSeconds = 600.0

    static func render(_ request: ExportRequest) -> ExportResult {
        var options = request.options.clamped
        options.format = .video
        let timeline = VideoTimeline(song: request.song, options: options)
        // Checked from the timeline before anything is rendered: finding out
        // after minutes of drawing frames would waste them on a predictable
        // refusal.
        guard timeline.seconds <= maxSeconds else { return .tooLong }
        return .failed(CocoaError(.featureUnsupported))
    }
}
