import SwiftUI
import UIKit

/// Draws one frame of an exported video with Core Graphics, in the app's own
/// colours and SF Mono. Sizes are fixed pixels from `VideoLayout`, not
/// Dynamic Type: the frame is a picture of the song, the same on every phone.
///
/// Grid: the current pattern scrolls up past a fixed playing row, as the
/// header video on the product page does. The row that is sounding is at
/// full colour; rows away from it dim into the background, so the eye stays
/// on the beat. Cover: a card with the title, tempo and length, a bar per
/// track that flashes on each note (`ChannelPulse`), and a progress bar.
/// Both carry the "Made with Chiptune" tag.
final class VideoFrameRenderer {
    private let song: Song
    private let style: ExportOptions.VideoStyle
    private let timeline: VideoTimeline
    private let layout: VideoLayout
    private let pulse: ChannelPulse

    init(song: Song, options: ExportOptions, timeline: VideoTimeline) {
        var song = song
        song.normalize()
        self.song = song
        style = options.videoStyle
        self.timeline = timeline
        layout = VideoLayout(trackCount: song.tracks.count)
        pulse = ChannelPulse(song: song, timeline: timeline)
    }

    /// Draws `frame` into `context`, which must be `VideoLayout.size` and
    /// flipped so y runs down from the top, as UIKit's are.
    func draw(frame: Int, in context: CGContext) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        drawBackground(in: context)
        switch style {
        case .grid: drawGrid(frame: frame, in: context)
        case .cover: drawCover(frame: frame, in: context)
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
        // In the ring-out nothing new plays, so the grid rests on the last
        // step and the playing row's highlight fades with the sound.
        let lastStep = timeline.stepsPerPass * timeline.loopCount - 1
        let elapsed = timeline.elapsedSteps(frame: frame)
        let inTail = timeline.position(frame: frame) == nil
        let globalStep = min(Int(elapsed), lastStep)
        guard let at = timeline.position(globalStep: globalStep),
              let pattern = song.patterns[safe: at.pattern] else { return }
        let fraction = inTail ? 0 : elapsed - Double(globalStep)
        let position = Double(at.step) + fraction
        let tailFade = inTail
            ? max(0, 1 - Double(timeline.sample(frame: frame) - timeline.bodySamples) / Double(max(timeline.tailSamples, 1)))
            : 1

        drawGridHeader(pattern: pattern, step: at.step)
        drawColumnHeaders()

        context.saveGState()
        context.clip(to: layout.gridRect)
        let band = UIBezierPath(roundedRect: layout.playheadRowRect, cornerRadius: layout.cellRadius + 4)
        Palette.text.withAlpha(0.10 * CGFloat(tailFade)).uiColor.setFill()
        band.fill()

        for step in layout.visibleSteps(position: position, patternLength: pattern.length) {
            let y = layout.rowCenterY(step: step, position: position)
            drawRow(pattern: pattern, step: step, centerY: y, light: rowLight(y: y))
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
        Self.text(song.name, size: layout.titleFontSize, weight: .bold, color: Palette.text,
                  in: CGRect(x: header.minX, y: header.minY, width: header.width, height: 72))
        let readout = "\(pattern.name)  ·  STEP \(String(format: "%02d", step))  ·  \(Int(song.tempo)) BPM"
        Self.text(readout, size: layout.subtitleFontSize, weight: .semibold, color: Palette.dim,
                  in: CGRect(x: header.minX, y: header.minY + 86, width: header.width, height: 44))
    }

    private func drawColumnHeaders() {
        for index in song.tracks.indices {
            let track = song.tracks[index]
            let cell = layout.cellRect(track: index, centerY: layout.columnHeaderY)
            let color = track.muted ? Palette.dim : Palette.channel(track.kind)
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

    // MARK: Cover

    private func drawCover(frame: Int, in context: CGContext) {
        let card = UIBezierPath(roundedRect: layout.coverCardRect, cornerRadius: Theme.panelRadius * 3)
        Palette.panel.uiColor.setFill()
        card.fill()
        Palette.grid.uiColor.setStroke()
        card.lineWidth = 2
        card.stroke()

        Self.text(song.name, size: layout.coverTitleFontSize, weight: .bold, color: Palette.text,
                  in: layout.coverTitleRect, lines: 2)
        let length = Self.clock(timeline.seconds)
        Self.text("\(Int(song.tempo)) BPM  ·  \(length)", size: layout.coverMetaFontSize, weight: .semibold,
                  color: Palette.dim, in: layout.coverMetaRect)

        let levels = pulse.levels(frame: frame)
        for index in song.tracks.indices {
            let track = song.tracks[index]
            let rect = layout.coverBarRect(track: index)
            let radius = min(rect.width / 2, 18)
            Palette.panelHigh.uiColor.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            let level = levels[safe: index] ?? 0
            if level > 0 {
                let height = max(rect.height * CGFloat(level), radius * 2)
                let lit = CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)
                Palette.channel(track.kind).uiColor.setFill()
                UIBezierPath(roundedRect: lit, cornerRadius: radius).fill()
            }
            let silent = MidiExport.isSilent(track)
            let labelRect = CGRect(x: rect.midX - 90, y: layout.coverBarLabelY - 20, width: 180, height: 40)
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
        Self.text(Self.clock(elapsed), size: 28, weight: .semibold, color: Palette.dim, in: times)
        Self.text(length, size: 28, weight: .semibold, color: Palette.dim, in: times, alignment: .right)
    }

    /// Whole seconds, "m:ss". `Format.clock` switches to tenths under ten
    /// seconds, which suits a static readout but makes a running clock change
    /// shape when it passes 0:10.
    private static func clock(_ seconds: Double) -> String {
        let whole = Int(max(seconds, 0))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: Tag

    private func drawTag() {
        Self.text("Made with Chiptune", size: VideoLayout.tagFontSize, weight: .semibold,
                  color: Palette.dim.withAlpha(0.8).flattened(over: Palette.background),
                  in: VideoLayout.tagRect)
    }

    // MARK: Text

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
