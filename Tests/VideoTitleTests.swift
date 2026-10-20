import XCTest
import UIKit
@testable import Chiptune

/// A song name with a line break in it. Typing can't make one, but an
/// imported .chipsong keeps whatever its name held, and `Song.normalize`
/// trims only the ends. The video draws such a name on one line, as the
/// app's own song list does, so neither style's title runs into what's
/// under it.
final class VideoTitleTests: XCTestCase {

    func testLineBreaksInANameAreDrawnAsSpaces() {
        XCTAssertEqual(VideoFrameRenderer.drawnName("A\nB"), "A B")
        XCTAssertEqual(VideoFrameRenderer.drawnName("Night\r\n\n  Drive"), "Night Drive")
        XCTAssertEqual(VideoFrameRenderer.drawnName("One\u{2028}Two"), "One Two")
        XCTAssertEqual(VideoFrameRenderer.drawnName("Plain  Name"), "Plain  Name")
    }

    /// The whole frame, drawn as the export draws it.
    private func pixels(of song: Song, style: ExportOptions.VideoStyle) -> Data {
        var options = ExportOptions()
        options.format = .video
        options.videoStyle = style
        let timeline = VideoTimeline(song: song, options: options)
        let renderer = VideoFrameRenderer(song: song, options: options, timeline: timeline)
        let width = Int(VideoLayout.size.width), height = Int(VideoLayout.size.height)
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: Palette.colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            renderer.draw(frame: 0, in: context)
        }
        return bytes
    }

    /// The Cartridge placed its tempo line under the title's first line
    /// when a short name broke onto a second, drawing the two over each
    /// other. The Grid's one-line header cut the name off at the break.
    func testANameWithALineBreakDrawsAsTheSameNameWithASpace() {
        var broken = TestSongs.empty(name: "A\nB", tempo: 240, length: 8)
        broken.patterns[0].rows[0][0] = 60
        var spaced = broken
        spaced.name = "A B"
        for style in [ExportOptions.VideoStyle.cover, .grid] {
            XCTAssertTrue(pixels(of: broken, style: style) == pixels(of: spaced, style: style),
                          "\(style): the broken name drew differently from the spaced one")
        }
    }
}
