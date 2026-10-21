import XCTest
import UIKit
@testable import Chiptune

/// What one 1080×1920 frame costs to draw, per style. A ten-minute video is
/// 18,000 of them, so a few milliseconds a frame is the difference between
/// a render the user waits through and one they give up on.
///
/// Prints its numbers rather than asserting a budget: the simulator's
/// timings swing with whatever else the Mac is doing. The one thing it
/// asserts is a ratio between two styles measured in the same run.
final class VideoFrameCostTests: XCTestCase {
    private func renderer(style: ExportOptions.VideoStyle,
                          cachesBackdrop: Bool = true) -> (VideoFrameRenderer, VideoTimeline) {
        let song = TestSongs.golden()
        var options = ExportOptions()
        options.format = .video
        options.videoStyle = style
        let timeline = VideoTimeline(song: song, options: options)
        return (VideoFrameRenderer(song: song, options: options, timeline: timeline,
                                   cachesBackdrop: cachesBackdrop), timeline)
    }

    /// One frame's pixels, drawn as the export draws it.
    private func pixels(_ renderer: VideoFrameRenderer, frame: Int) -> [UInt8] {
        let width = Int(VideoLayout.size.width), height = Int(VideoLayout.size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var drew = false
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: Palette.colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            renderer.draw(frame: frame, in: context)
            drew = true
        }
        XCTAssertTrue(drew, "couldn't make a bitmap context")
        return bytes
    }

    /// The Cartridge's still parts (the plastic, its shadow, the title and
    /// tempo line) are drawn once and copied into each frame. The copy has
    /// to be the same picture the direct drawing made, frame after frame.
    func testCachedCartridgeFramesMatchDrawingEveryPartEachFrame() throws {
        let (cached, timeline) = renderer(style: .cover)
        let (direct, _) = renderer(style: .cover, cachesBackdrop: false)
        let last = max(timeline.totalFrames - 1, 0)
        for frame in [0, 1, last / 3, last / 2, last] {
            let a = pixels(cached, frame: frame)
            let b = pixels(direct, frame: frame)
            guard a.count == b.count else { return XCTFail("frame \(frame): sizes differ") }
            var worst = 0, differing = 0
            for i in a.indices where a[i] != b[i] {
                differing += 1
                worst = max(worst, abs(Int(a[i]) - Int(b[i])))
            }
            XCTAssertLessThanOrEqual(worst, 1, "frame \(frame): a channel moved by \(worst)")
            XCTAssertLessThan(differing, 64, "frame \(frame): \(differing) channels differ")
        }
    }

    /// Drawn once for the whole render, however many frames follow.
    func testTheCartridgeBackdropIsDrawnOnce() {
        let (renderer, timeline) = renderer(style: .cover)
        for frame in 0..<min(10, timeline.totalFrames) { _ = pixels(renderer, frame: frame) }
        XCTAssertEqual(renderer.backdropDraws, 1)
    }

    /// Milliseconds for each of `frames` frames, drawn one at a time. The
    /// median is read, so one frame slowed by whatever else the Mac is doing
    /// doesn't decide the number.
    private func frameTimes(style: ExportOptions.VideoStyle, cachesBackdrop: Bool = true,
                            frames: Int = 31) -> [Double] {
        let (renderer, timeline) = renderer(style: style, cachesBackdrop: cachesBackdrop)
        let width = Int(VideoLayout.size.width), height = Int(VideoLayout.size.height)
        var bytes = Data(count: width * height * 4)
        var times: [Double] = []
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: Palette.colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            renderer.draw(frame: 0, in: context)   // warm caches and fonts
            for frame in 0..<frames {
                let start = DispatchTime.now().uptimeNanoseconds
                renderer.draw(frame: frame % max(timeline.totalFrames, 1), in: context)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
        }
        XCTAssertEqual(times.count, frames, "couldn't make a bitmap context")
        return times
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Prints both styles' costs, and holds the Cartridge's cache to what it
    /// is for: copying the still parts in has to cost well under drawing them
    /// each frame. Both are measured in the same run, so a busy Mac slows
    /// both and the ratio still holds.
    func testFrameCostPerStyle() {
        let grid = median(frameTimes(style: .grid))
        let cartridge = median(frameTimes(style: .cover))
        let uncached = median(frameTimes(style: .cover, cachesBackdrop: false))
        print(String(format: "VIDEO FRAME COST: grid %.2f ms, cartridge %.2f ms, cartridge uncached %.2f ms",
                     grid, cartridge, uncached))
        XCTAssertGreaterThan(grid, 0)
        XCTAssertGreaterThan(cartridge, 0)
        XCTAssertLessThan(cartridge, uncached / 2,
                          "the cached Cartridge frame should cost under half the uncached one")
    }
}
