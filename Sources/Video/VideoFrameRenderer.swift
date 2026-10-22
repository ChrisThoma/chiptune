import SwiftUI
import UIKit

/// Draws one frame of an exported video with Core Graphics, in the app's own
/// colours and SF Mono. Sizes are fixed pixels from `VideoLayout`, not
/// Dynamic Type: the frame is a picture of the song, the same on every phone.
///
/// Grid: the song's steps, across patterns and passes, scroll up past a
/// fixed playing row (`GridFrame`), as the header video on the product page
/// does. The row that is sounding is at
/// full colour; rows away from it dim into the background, so the eye stays
/// on the beat. Cover (shown as "Cartridge"): a grey game cartridge whose
/// label carries the title, tempo and length, a bar per track that flashes
/// on each note (`ChannelPulse`), and a progress bar.
/// Both carry the "Made with Chiptune" tag.
final class VideoFrameRenderer {
    private let song: Song
    private let style: ExportOptions.VideoStyle
    private let timeline: VideoTimeline
    private let layout: VideoLayout
    private let pulse: ChannelPulse
    private let cachesBackdrop: Bool
    /// The Cartridge's still parts, drawn on the first frame. See
    /// `drawCoverBackdrop`.
    private var backdrop: CGImage?
    /// How many times the Cartridge's still parts have been drawn, for a
    /// test that they're drawn once.
    private(set) var backdropDraws = 0

    /// `cachesBackdrop` false draws every part of every frame, the picture a
    /// test compares the cached frames against. The app never passes it.
    init(song: Song, options: ExportOptions, timeline: VideoTimeline, cachesBackdrop: Bool = true) {
        var song = song
        song.normalize()
        self.song = song
        style = options.videoStyle
        self.timeline = timeline
        self.cachesBackdrop = cachesBackdrop
        layout = VideoLayout(trackCount: song.tracks.count)
        pulse = ChannelPulse(song: song, timeline: timeline)
    }

    /// Draws `frame` into `context`, which must be `VideoLayout.size` and
    /// flipped so y runs down from the top, as UIKit's are.
    func draw(frame: Int, in context: CGContext) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        switch style {
        case .grid:
            drawBackground(in: context)
            drawGrid(frame: frame, in: context)
        case .cover:
            drawCoverBackdrop(in: context)
            drawCover(frame: frame, in: context)
        }
        drawTag()
    }

    // MARK: Background

    /// Flat Theme.background. A soft radial lift was tried and H.264 turned
    /// it into visible blocks on a dark field this close to black.
    private func drawBackground(in context: CGContext) {
        context.setFillColor(Palette.background.cg)
        context.fill(CGRect(origin: .zero, size: VideoLayout.size))
    }

    // MARK: Grid

    private func drawGrid(frame: Int, in context: CGContext) {
        guard let grid = GridFrame(layout: layout, timeline: timeline, frame: frame),
              let playing = song.patterns[safe: grid.playing.pattern] else { return }

        drawGridHeader(pattern: playing, step: grid.playing.step)
        drawColumnHeaders()

        context.saveGState()
        context.clip(to: layout.gridRect)
        let band = UIBezierPath(roundedRect: grid.band, cornerRadius: layout.cellRadius + 4)
        Palette.text.withAlpha(0.10 * CGFloat(grid.bandLight)).uiColor.setFill()
        band.fill()

        for row in grid.rows {
            guard let pattern = song.patterns[safe: row.pattern] else { continue }
            drawRow(pattern: pattern, step: row.step, centerY: row.centerY, light: rowLight(y: row.centerY))
        }
        context.restoreGState()
    }

    /// Full on the playing row, easing to about 40% a row away, then fading
    /// out toward the grid's top and bottom edges.
    private func rowLight(y: CGFloat) -> Double {
        let distance = Double(abs(y - layout.playheadY))
        var near = max(0, 1 - distance / Double(layout.rowPitch * 1.1))
        near = near * near * (3 - 2 * near)
        let base = 0.42 + 0.58 * near
        let half = Double(layout.gridRect.height / 2)
        var edge = min(1, max(0, (half - distance) / (half * 0.55)))
        edge = edge * edge * (3 - 2 * edge)
        return base * edge
    }

    private func drawGridHeader(pattern: Pattern, step: Int) {
        let header = layout.headerRect
        Self.text(Self.drawnName(song.name), size: layout.titleFontSize, weight: .bold, color: Palette.text,
                  in: CGRect(x: header.minX, y: header.minY, width: header.width, height: 72))
        let readout = "\(pattern.name)  ·  STEP \(String(format: "%02d", step))  ·  \(Int(song.tempo)) BPM"
        Self.text(readout, size: layout.subtitleFontSize, weight: .semibold, color: Palette.dim,
                  in: CGRect(x: header.minX, y: header.minY + 86, width: header.width, height: 44))
    }

    private func drawColumnHeaders() {
        for index in song.tracks.indices {
            let track = song.tracks[index]
            let cell = layout.columnHeaderRect(track: index)
            let color = Self.dimsName(of: track, in: .grid) ? Palette.dim : Palette.channel(track.kind)
            Self.text(song.label(for: index), size: layout.columnHeaderFontSize, weight: .bold,
                      color: color, in: cell, alignment: .center)
        }
    }

    /// One step's gutter number and cells, after GridCell: a note fills with
    /// its channel colour and is named in dark text; a note-off is a dim
    /// REST; an empty step is the row tint with a hairline and a dot. Muted
    /// tracks fade their notes to 35% as the app does. `light` blends the
    /// whole row toward the background.
    private func drawRow(pattern: Pattern, step: Int, centerY: CGFloat, light: Double) {
        guard light > 0.004 else { return }
        let bg = Palette.background
        let gutter = layout.gutterRect(centerY: centerY)
        Self.text(String(format: "%02d", step), size: layout.gutterFontSize, weight: .medium,
                  color: (step % 4 == 0 ? Palette.text : Palette.dim).blended(over: bg, light),
                  in: gutter, alignment: .center)

        for index in song.tracks.indices {
            let track = song.tracks[index]
            let note = pattern.rows[safe: index]?[safe: step] ?? Chip.emptyNote
            let rect = layout.cellRect(track: index, centerY: centerY)
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: layout.cellRadius)
            let filled = note != Chip.emptyNote
            let fill: RGBA
            let label: String
            let labelColor: RGBA
            if filled {
                let base = note == Chip.noteOff ? Palette.dim : Palette.channel(track.kind)
                fill = track.muted ? base.withAlpha(0.35).flattened(over: bg) : base
                label = NoteName.label(note)
                labelColor = (track.muted ? Palette.text : Palette.onLight).withAlpha(0.85).flattened(over: fill)
            } else {
                fill = step % 4 == 0 ? Palette.panelHigh : Palette.panel
                label = "·"
                labelColor = Palette.dim.withAlpha(0.6).flattened(over: fill)
            }
            fill.blended(over: bg, light).uiColor.setFill()
            shape.fill()
            if !filled {
                Palette.grid.withAlpha(0.6).flattened(over: fill).blended(over: bg, light).uiColor.setStroke()
                shape.lineWidth = 2
                shape.stroke()
            }
            let size = note == Chip.noteOff ? layout.cellFontSize * 0.8 : (filled ? layout.cellFontSize : layout.cellFontSize * 1.3)
            Self.text(label, size: size, weight: .semibold, color: labelColor.blended(over: bg, light),
                      in: rect, alignment: .center)
        }
    }

    // MARK: Cartridge (the Cover style)

    /// Grey plastic, lit from the top left: flat fills only, since H.264
    /// bands gradients.
    private enum Plastic {
        static let body = RGBA(r: 0xBD / 255, g: 0xBA / 255, b: 0xB3 / 255)
        static let highlight = RGBA(r: 0xDA / 255, g: 0xD7 / 255, b: 0xD0 / 255)
        static let shade = RGBA(r: 0x8E / 255, g: 0x8B / 255, b: 0x84 / 255)
        static let groove = RGBA(r: 0x9E / 255, g: 0x9B / 255, b: 0x94 / 255)
        static let bevel = RGBA(r: 0xA8 / 255, g: 0xA5 / 255, b: 0x9E / 255)
        static let recessDark = RGBA(r: 0x7C / 255, g: 0x79 / 255, b: 0x73 / 255)
    }
    /// How far the lit and shaded edges reach in from the outline.
    private static let edge: CGFloat = 7

    /// The body with its notch, the grip ridges, the sunken label and the
    /// moulded arrow. The song's own content is drawn on the label after.
    private func drawCartridge(in context: CGContext) {
        let cart = layout.cartridgeRect
        let body = Self.cartridgePath(cart, notch: layout.cartridgeNotch, radius: layout.cartridgeCornerRadius)

        // A soft shadow under the whole body.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 26), blur: 60,
                          color: UIColor.black.withAlphaComponent(0.7).cgColor)
        Plastic.shade.uiColor.setFill()
        body.fill()
        context.restoreGState()

        // Edges: lit top and left, shaded bottom and right, then the face.
        context.saveGState()
        body.addClip()
        Plastic.highlight.uiColor.setFill()
        body.fill()
        Plastic.shade.uiColor.setFill()
        Self.cartridgePath(cart.offsetBy(dx: Self.edge, dy: Self.edge), notch: layout.cartridgeNotch,
                           radius: layout.cartridgeCornerRadius).fill()
        Plastic.body.uiColor.setFill()
        Self.cartridgePath(cart.insetBy(dx: Self.edge, dy: Self.edge), notch: layout.cartridgeNotch - 3,
                           radius: layout.cartridgeCornerRadius - Self.edge).fill()
        context.restoreGState()

        // Grip ridges: a groove with a lit lip under it.
        for ridge in layout.gripRidgeRects {
            Plastic.groove.uiColor.setFill()
            UIBezierPath(roundedRect: ridge, cornerRadius: ridge.height / 2).fill()
            Plastic.highlight.uiColor.setFill()
            UIBezierPath(roundedRect: CGRect(x: ridge.minX, y: ridge.maxY, width: ridge.width, height: 3),
                         cornerRadius: 1.5).fill()
        }

        // The recess: shaded on its top and left, where the rim overhangs,
        // lit on its bottom and right.
        let recess = layout.labelRecessRect
        let recessRadius: CGFloat = 22
        let recessPath = UIBezierPath(roundedRect: recess, cornerRadius: recessRadius)
        context.saveGState()
        recessPath.addClip()
        Plastic.highlight.uiColor.setFill()
        recessPath.fill()
        Plastic.recessDark.uiColor.setFill()
        UIBezierPath(roundedRect: recess.offsetBy(dx: -5, dy: -5), cornerRadius: recessRadius).fill()
        Plastic.bevel.uiColor.setFill()
        UIBezierPath(roundedRect: recess.insetBy(dx: 5, dy: 5), cornerRadius: recessRadius - 5).fill()
        context.restoreGState()

        // The label itself, on the app's own background.
        Palette.background.uiColor.setFill()
        UIBezierPath(roundedRect: layout.labelRect, cornerRadius: 12).fill()

        // The arrow moulded under the label: a slightly sunken triangle with
        // a lit lower edge.
        let tri = layout.triangleRect
        Plastic.highlight.uiColor.setFill()
        Self.triangle(tri.offsetBy(dx: 0, dy: 3)).fill()
        Plastic.groove.uiColor.setFill()
        Self.triangle(tri).fill()
    }

    /// A cartridge outline in `rect`: the top-right corner cut by a diagonal
    /// `notch` long on each leg, the other three rounded by `radius`.
    private static func cartridgePath(_ rect: CGRect, notch: CGFloat, radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius,
                    startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notch))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
                    startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius,
                    startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.close()
        return path
    }

    /// An upward-pointing triangle filling `rect`.
    private static func triangle(_ rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }

    /// Everything in a Cartridge frame that doesn't move: the background,
    /// the plastic with its shadow, the title and the tempo line. The
    /// shadow's 60 pt blur made this most of a frame's cost, so it is drawn
    /// once into an image and that image is copied into every frame after,
    /// as the Android renderer does.
    private func drawCoverBackdrop(in context: CGContext) {
        guard cachesBackdrop else { return drawStillCover(in: context) }
        if backdrop == nil { backdrop = makeBackdrop() }
        guard let backdrop else { return drawStillCover(in: context) }
        // The frame's context is flipped; an image draws in unflipped space.
        // The copy is pixel for pixel, so nothing is blended or smoothed.
        context.saveGState()
        context.translateBy(x: 0, y: VideoLayout.size.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(backdrop, in: CGRect(origin: .zero, size: VideoLayout.size))
        context.restoreGState()
    }

    /// The still parts in a bitmap made the way `VideoExport` makes each
    /// frame's: sRGB, BGRA, flipped so y runs down.
    private func makeBackdrop() -> CGImage? {
        let width = Int(VideoLayout.size.width), height = Int(VideoLayout.size.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: Palette.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        drawStillCover(in: context)
        UIGraphicsPopContext()
        return context.makeImage()
    }

    private func drawStillCover(in context: CGContext) {
        backdropDraws += 1
        drawBackground(in: context)
        drawCartridge(in: context)

        let titleRect = layout.coverTitleRect
        let title = Self.drawnName(song.name)
        Self.text(title, size: layout.coverTitleFontSize, weight: .bold, color: Palette.text,
                  in: titleRect, lines: 2)
        // The tempo line sits under the title as drawn, so a one-line title
        // doesn't leave a gap where a second line would go. Measuring the
        // unbroken width is only right because `drawnName` leaves no line
        // breaks to start a second line on their own.
        let titleFont = UIFont.monospacedSystemFont(ofSize: layout.coverTitleFontSize, weight: .bold)
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let titleLines: CGFloat = titleWidth > titleRect.width ? 2 : 1
        var meta = layout.coverMetaRect
        meta.origin.y = min(meta.minY, titleRect.minY + titleLines * titleFont.lineHeight + 8)
        let length = VideoClock.total(timeline.seconds)
        Self.text("\(Int(song.tempo)) BPM  ·  \(length)", size: layout.coverMetaFontSize, weight: .semibold,
                  color: Palette.dim, in: meta)
    }

    /// The parts of a Cartridge frame that move, over its backdrop.
    private func drawCover(frame: Int, in context: CGContext) {
        let length = VideoClock.total(timeline.seconds)
        let levels = pulse.levels(frame: frame)
        for index in song.tracks.indices {
            let track = song.tracks[index]
            let segments = layout.coverBarSegments(track: index)
            let lit = ChannelPulse.litSegments(level: levels[safe: index] ?? 0, of: segments.count)
            for (row, segment) in segments.enumerated() {
                let color = row < lit ? Self.segmentColor(Palette.channel(track.kind), row: row, of: segments.count)
                                      : Palette.panelHigh
                color.uiColor.setFill()
                UIBezierPath(roundedRect: segment, cornerRadius: Self.segmentRadius).fill()
            }
            let silent = Self.dimsName(of: track, in: .cover)
            let labelRect = layout.coverBarLabelRect(track: index)
            Self.text(song.label(for: index), size: layout.coverLabelFontSize, weight: .bold,
                      color: silent ? Palette.dim : Palette.channel(track.kind), in: labelRect, alignment: .center)
        }

        let track = layout.coverProgressRect
        Palette.panelHigh.uiColor.setFill()
        UIBezierPath(roundedRect: track, cornerRadius: track.height / 2).fill()
        let done = min(1, Double(timeline.sample(frame: frame)) / Double(max(timeline.totalSamples, 1)))
        if done > 0 {
            let fill = CGRect(x: track.minX, y: track.minY,
                              width: max(track.width * CGFloat(done), track.height), height: track.height)
            Palette.text.uiColor.setFill()
            UIBezierPath(roundedRect: fill, cornerRadius: track.height / 2).fill()
        }
        let times = layout.coverTimeRect
        let elapsed = min(Double(timeline.sample(frame: frame)) / WavExport.sampleRate, timeline.seconds)
        let elapsedText = VideoClock.elapsed(elapsed, total: timeline.seconds,
                                             isFinalFrame: frame >= timeline.totalFrames - 1)
        Self.text(elapsedText, size: 28, weight: .semibold, color: Palette.dim, in: times)
        Self.text(length, size: 28, weight: .semibold, color: Palette.dim, in: times, alignment: .right)
    }

    static let segmentRadius: CGFloat = 6

    /// A lit segment's colour: the channel's at the bottom, a little darker
    /// up the stack, as the app icon's bars are.
    static func segmentColor(_ channel: RGBA, row: Int, of count: Int) -> RGBA {
        let height = CGFloat(row) / CGFloat(max(count - 1, 1))
        return channel.withAlpha(1 - 0.2 * height).flattened(over: Palette.background)
    }

    /// Whether a track's name is drawn dim, as one the soundtrack doesn't
    /// play: muted, or at a volume the MIDI export calls silent. The same
    /// rule in both styles, and the one that keeps a Cartridge bar dark.
    static func dimsName(of track: Track, in style: ExportOptions.VideoStyle) -> Bool {
        MidiExport.isSilent(track)
    }

    // MARK: Tag

    private func drawTag() {
        Self.text("Made with Chiptune", size: VideoLayout.tagFontSize, weight: .semibold,
                  color: Palette.dim.withAlpha(0.8).flattened(over: Palette.background),
                  in: VideoLayout.tagRect)
    }

    // MARK: Text

    /// The song's name on one line, its line breaks drawn as spaces. Typing
    /// can't put a break in a name, but an imported .chipsong keeps whatever
    /// its name held and `Song.normalize` trims only the ends. Drawn as is,
    /// the Cartridge put its tempo line under the first line of a short
    /// broken title, over the second, and the Grid's one-line header showed
    /// only what came before the break. The app's song list shows names on
    /// one line too.
    static func drawnName(_ name: String) -> String {
        name.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// SF Mono, vertically centred in `rect` for a single line, truncated
    /// rather than spilling out of it.
    private static func text(_ string: String, size: CGFloat, weight: UIFont.Weight, color: RGBA,
                             in rect: CGRect, alignment: NSTextAlignment = .left, lines: Int = 1) {
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color.uiColor, .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: string, attributes: attributes)
        if lines == 1 {
            let height = font.lineHeight
            text.draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        } else {
            text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
    }
}

/// Theme's colours as plain components, so the renderer can blend them
/// toward the background itself instead of drawing every cell through a
/// transparency layer.
struct RGBA: Equatable {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: r, g: g, b: b, a: a)
    }

    func withAlpha(_ alpha: CGFloat) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    /// This colour, at its alpha, composited onto an opaque `base`.
    func flattened(over base: RGBA) -> RGBA {
        RGBA(r: base.r + (r - base.r) * a, g: base.g + (g - base.g) * a, b: base.b + (b - base.b) * a)
    }

    func mixed(toward other: RGBA, by amount: CGFloat) -> RGBA {
        RGBA(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// Shown at `light` (0...1) over `base`: 1 is this colour, 0 is `base`.
    func blended(over base: RGBA, _ light: Double) -> RGBA {
        base.mixed(toward: self, by: CGFloat(light))
    }

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { CGColor(colorSpace: Palette.colorSpace, components: [r, g, b, a]) ?? uiColor.cgColor }
}

/// `Theme`, read once.
enum Palette {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let background = RGBA(Theme.background)
    static let panel = RGBA(Theme.panel)
    static let panelHigh = RGBA(Theme.panelHigh)
    static let grid = RGBA(Theme.grid)
    static let text = RGBA(Theme.text)
    static let dim = RGBA(Theme.dim)
    static let onLight = RGBA(Theme.onLight)
    private static let channels = ChannelKind.allCases.map { RGBA(Theme.color(for: $0)) }

    static func channel(_ kind: ChannelKind) -> RGBA { channels[kind.rawValue] }
}
