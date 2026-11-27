import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The pitch-effect marks, drawn as strokes rather than font characters, and
/// where they sit next to a note name. The one place this geometry lives: the
/// grid cell, its context menu and the Grid video all draw from here.
///
/// A mark is a stroked path in a unit box (0...1, y down). In a label the box
/// is a square as tall as the font's cap height, a small gap after the name,
/// with its bottom on the text baseline. Name and mark are centered together
/// and shrink together when they don't fit.
enum EffectMark {

    /// Stroke width as a fraction of the box side; about the weight of the
    /// semibold label's own strokes.
    static let lineWidthRatio: CGFloat = 0.14
    /// The gap between name and mark, as a fraction of the font size.
    static let gapRatio: CGFloat = 0.1
    /// What a grid cell keeps clear around its label, in total across both sides.
    static let cellPadding: CGFloat = 8

    // MARK: Paths

    /// The mark in a unit box, y down; nil for no effect.
    static func unitPath(_ effect: NoteEffect) -> CGPath? {
        let p = CGMutablePath()
        switch effect {
        case .none:
            return nil
        case .slideUp:
            // ↗
            p.move(to: CGPoint(x: 0.15, y: 0.85))
            p.addLine(to: CGPoint(x: 0.85, y: 0.15))
            p.move(to: CGPoint(x: 0.4, y: 0.15))
            p.addLine(to: CGPoint(x: 0.85, y: 0.15))
            p.addLine(to: CGPoint(x: 0.85, y: 0.6))
        case .slideDown:
            // ↘
            p.move(to: CGPoint(x: 0.15, y: 0.15))
            p.addLine(to: CGPoint(x: 0.85, y: 0.85))
            p.move(to: CGPoint(x: 0.4, y: 0.85))
            p.addLine(to: CGPoint(x: 0.85, y: 0.85))
            p.addLine(to: CGPoint(x: 0.85, y: 0.4))
        case .vibrato:
            // ~ : one full wave across the box.
            p.move(to: CGPoint(x: 0.08, y: 0.55))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.5),
                       control1: CGPoint(x: 0.18, y: 0.2), control2: CGPoint(x: 0.38, y: 0.2))
            p.addCurve(to: CGPoint(x: 0.92, y: 0.45),
                       control1: CGPoint(x: 0.62, y: 0.8), control2: CGPoint(x: 0.82, y: 0.8))
        case .glide:
            // ⌒ : a low arch.
            p.move(to: CGPoint(x: 0.1, y: 0.7))
            p.addQuadCurve(to: CGPoint(x: 0.9, y: 0.7), control: CGPoint(x: 0.5, y: 0.1))
        case .bendIn:
            // ⤴ : comes in level, turns up into an arrow.
            p.move(to: CGPoint(x: 0.1, y: 0.85))
            p.addLine(to: CGPoint(x: 0.45, y: 0.85))
            p.addQuadCurve(to: CGPoint(x: 0.72, y: 0.55), control: CGPoint(x: 0.72, y: 0.85))
            p.addLine(to: CGPoint(x: 0.72, y: 0.12))
            p.move(to: CGPoint(x: 0.47, y: 0.37))
            p.addLine(to: CGPoint(x: 0.72, y: 0.12))
            p.addLine(to: CGPoint(x: 0.97, y: 0.37))
        }
        return p
    }

    /// The mark scaled into `rect`.
    static func path(_ effect: NoteEffect, in rect: CGRect) -> CGPath? {
        guard let unit = unitPath(effect) else { return nil }
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width, y: rect.height)
        return unit.copy(using: &t)
    }

    /// Strokes the mark into a Core Graphics context, for the video and the
    /// menu icons.
    static func stroke(_ effect: NoteEffect, in rect: CGRect, color: CGColor, context: CGContext) {
        guard let path = path(effect, in: rect) else { return }
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color)
        context.setLineWidth(rect.height * lineWidthRatio)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: Metrics

    static func font(size: CGFloat) -> PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: size, weight: .semibold)
    }

    /// The side of the mark's square box: the font's cap height.
    static func side(fontSize: CGFloat) -> CGFloat {
        font(size: fontSize).capHeight
    }

    static func gap(fontSize: CGFloat) -> CGFloat {
        fontSize * gapRatio
    }

    static func nameWidth(_ name: String, fontSize: CGFloat) -> CGFloat {
        ceil((name as NSString).size(withAttributes: [.font: font(size: fontSize)]).width)
    }

    /// Name, gap and mark side by side; just the name for no effect.
    static func labelWidth(name: String, effect: NoteEffect, fontSize: CGFloat) -> CGFloat {
        let text = nameWidth(name, fontSize: fontSize)
        guard effect != .none else { return text }
        return text + gap(fontSize: fontSize) + side(fontSize: fontSize)
    }

    /// The factor that shrinks name and mark together to fit `available`;
    /// 1 when they already fit.
    static func fitScale(name: String, effect: NoteEffect, fontSize: CGFloat, available: CGFloat) -> CGFloat {
        let width = labelWidth(name: name, effect: effect, fontSize: fontSize)
        guard width > available, width > 0 else { return 1 }
        return max(0.1, available / width)
    }

    struct Layout: Equatable {
        var fontSize: CGFloat
        /// The name's line box, one line of the font tall.
        var nameRect: CGRect
        var baseline: CGFloat
        var gap: CGFloat
        /// The mark's box, bottom on the baseline; empty for no effect.
        var markRect: CGRect
    }

    /// Where a marked label goes in `rect`: centered as one, vertically
    /// centered on the font's line, shrunk to fit the width.
    static func layout(name: String, effect: NoteEffect, fontSize: CGFloat, in rect: CGRect) -> Layout {
        let size = fontSize * fitScale(name: name, effect: effect, fontSize: fontSize, available: rect.width)
        let font = font(size: size)
        let text = nameWidth(name, fontSize: size)
        let total = labelWidth(name: name, effect: effect, fontSize: size)
        let top = rect.midY - font.lineHeight / 2
        let baseline = top + font.ascender
        let nameRect = CGRect(x: rect.midX - total / 2, y: top, width: text, height: font.lineHeight)
        let gap = effect == .none ? 0 : gap(fontSize: size)
        let side = effect == .none ? 0 : font.capHeight
        let markRect = CGRect(x: nameRect.maxX + gap, y: baseline - side, width: side, height: side)
        return Layout(fontSize: size, nameRect: nameRect, baseline: baseline, gap: gap, markRect: markRect)
    }

    // MARK: Menu icons

    #if os(iOS)
    @MainActor private static var images: [NoteEffect: UIImage] = [:]

    /// The mark as a template image for a menu's icon slot, which takes only
    /// images.
    @MainActor
    static func image(_ effect: NoteEffect) -> Image {
        if let cached = images[effect] { return Image(uiImage: cached) }
        let side: CGFloat = 18
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            stroke(effect, in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4),
                   color: UIColor.black.cgColor, context: ctx.cgContext)
        }.withRenderingMode(.alwaysTemplate)
        images[effect] = image
        return Image(uiImage: image)
    }
    #else
    @MainActor private static var images: [NoteEffect: NSImage] = [:]

    /// The same mark for an AppKit menu. `isTemplate` is what lets the menu
    /// tint it for its own light, dark and highlighted rows.
    @MainActor
    static func image(_ effect: NoteEffect) -> Image {
        if let cached = images[effect] { return Image(nsImage: cached) }
        let side: CGFloat = 18
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            stroke(effect, in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4),
                   color: NSColor.black.cgColor, context: context)
            return true
        }
        image.isTemplate = true
        images[effect] = image
        return Image(nsImage: image)
    }
    #endif
}

/// The mark as a SwiftUI shape, for the grid cell. Stroke it with
/// `EffectMark.lineWidthRatio` of its height.
struct EffectMarkShape: Shape {
    let effect: NoteEffect

    func path(in rect: CGRect) -> Path {
        EffectMark.path(effect, in: rect).map(Path.init) ?? Path()
    }
}
