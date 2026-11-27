import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Chiptune

/// One Grid frame and one Cartridge frame, compared with PNGs the iOS run
/// wrote to `Tests/Fixtures`. On iOS this is a change detector for the
/// renderer; on macOS it is what says the Mac's video looks like the
/// phone's: same layout, colours, shapes and text, the right way up.
///
/// Fonts antialias a little differently between the two systems, so the
/// comparison allows small per-pixel differences and a small share of
/// pixels that differ more, at glyph edges. Text drawn upside down, a
/// shape swept the wrong way or a colour off by a step fails it.
final class VideoFrameParityTests: XCTestCase {

    /// The golden song, with an effect mark, a note-off and a muted track
    /// so every kind of cell the Grid draws is in the frame.
    private func song() -> Song {
        var song = TestSongs.golden()
        song.name = "Parity Check"
        song.patterns[0].setEffect(.vibrato, track: 0, step: 10)
        song.patterns[0].setEffect(.slideUp, track: 1, step: 11)
        song.patterns[0].rows[2][13] = Chip.noteOff
        song.tracks[3].muted = true
        return song
    }

    private func frame(style: ExportOptions.VideoStyle) throws -> CGImage {
        let song = song()
        var options = ExportOptions()
        options.format = .video
        options.videoStyle = style
        let timeline = VideoTimeline(song: song, options: options)
        let renderer = VideoFrameRenderer(song: song, options: options, timeline: timeline)
        let width = Int(VideoLayout.size.width), height = Int(VideoLayout.size.height)
        // Made as VideoExport makes each frame: sRGB BGRA, flipped so y runs down.
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: Palette.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        // A third of the way in: steps 6-15 on screen (the marks and the
        // note-off among them), notes lit, the progress bar part filled.
        renderer.draw(frame: timeline.totalFrames / 3, in: context)
        return try XCTUnwrap(context.makeImage())
    }

    // MARK: Fixtures

    /// Written only by the iOS run: the phone's picture is the reference.
    /// `CHIPTUNE_REGEN_FRAMES` is on the Chiptune scheme, off; a missing
    /// fixture also writes one, as GoldenRenderTests does.
    private func shouldRegenerate(_ name: String) -> Bool {
        #if os(iOS)
        if ProcessInfo.processInfo.environment["CHIPTUNE_REGEN_FRAMES"] == "1" { return true }
        return !FileManager.default.fileExists(atPath: FixtureFiles.repoDirectory.appendingPathComponent(name).path)
        #else
        return false
        #endif
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "couldn't write \(url.lastPathComponent)")
    }

    private func readPNG(_ name: String) throws -> CGImage {
        let url = try FixtureFiles.url(name)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// The image's pixels as sRGB BGRA bytes, however the PNG stored them.
    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var out = [UInt8](repeating: 0, count: width * height * 4)
        try out.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: Palette.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    // MARK: Comparison

    struct Difference {
        /// The largest change in any one channel, 0...255.
        var max: Int
        /// The average change per channel over the whole frame.
        var mean: Double
        /// The share of pixels with a channel more than `farThreshold` off.
        var farShare: Double
    }

    /// More than this on a channel is beyond antialiasing at a glyph's edge
    /// shifting by a fraction of a pixel.
    static let farThreshold = 64

    private func difference(_ a: [UInt8], _ b: [UInt8]) -> Difference {
        var maxDiff = 0, sum = 0, far = 0
        var i = 0
        while i < a.count {
            var pixelFar = false
            for c in 0..<4 {
                let d = abs(Int(a[i + c]) - Int(b[i + c]))
                sum += d
                if d > maxDiff { maxDiff = d }
                if d > Self.farThreshold { pixelFar = true }
            }
            if pixelFar { far += 1 }
            i += 4
        }
        return Difference(max: maxDiff, mean: Double(sum) / Double(a.count), farShare: Double(far) / Double(a.count / 4))
    }

    private func assertMatchesFixture(style: ExportOptions.VideoStyle, name: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let drawn = try frame(style: style)
        if shouldRegenerate(name) {
            try writePNG(drawn, to: FixtureFiles.repoDirectory.appendingPathComponent(name))
            print("VideoFrameParityTests: regenerated \(name)")
            return
        }
        let fixture = try readPNG(name)
        XCTAssertEqual(fixture.width, drawn.width, file: file, line: line)
        XCTAssertEqual(fixture.height, drawn.height, file: file, line: line)
        let diff = difference(try bytes(drawn), try bytes(fixture))
        print(String(format: "VideoFrameParityTests %@: max %d, mean %.4f, far pixels %.4f%%",
                     name, diff.max, diff.mean, diff.farShare * 100))
        // macOS 27 against the iOS 27.1 simulator's fixture measured a mean
        // of 0.17-0.22 and 0.15-0.17% of pixels far off: SF Mono's vertical
        // metrics differ between the systems (ascender 0.967 em on the Mac,
        // 0.952 on iOS), so Mac text sits 1-2 px lower in its line, and its
        // glyph edges are what differ. Text drawn upside down measured a mean
        // of 0.8-1.8 and 0.7-1.3% far off.
        XCTAssertLessThan(diff.mean, 0.4, "\(name): mean channel difference", file: file, line: line)
        XCTAssertLessThan(diff.farShare, 0.003, "\(name): share of pixels far off", file: file, line: line)
    }

    func testAGridFrameMatchesTheFixture() throws {
        try assertMatchesFixture(style: .grid, name: "video-frame-grid.png")
    }

    func testACartridgeFrameMatchesTheFixture() throws {
        try assertMatchesFixture(style: .cover, name: "video-frame-cartridge.png")
    }
}
