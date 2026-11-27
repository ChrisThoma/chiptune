import CoreGraphics

/// The few UIKit drawing types the video renderer and `EffectMark` use, named
/// once per platform so one renderer draws the same frame on iOS and macOS.
///
/// On iOS these are UIKit's own types and nothing changes. On macOS the
/// AppKit equivalents get UIKit's names for the calls the renderer makes, so
/// its drawing code reads the same on both.
#if os(iOS)
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformBezierPath = UIBezierPath

enum PlatformGraphics {
    /// Makes `context` the one fills, strokes and text draw into. It must
    /// already be flipped so y runs down, as UIKit's are.
    static func push(_ context: CGContext) { UIGraphicsPushContext(context) }
    static func pop() { UIGraphicsPopContext() }
    static var currentContext: CGContext? { UIGraphicsGetCurrentContext() }
}

#elseif os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformBezierPath = NSBezierPath

enum PlatformGraphics {
    /// AppKit's current context is a stack too, but it has to be told the
    /// CGContext is flipped. Without `flipped: true` text draws upside down
    /// in the y-down space every frame is drawn in.
    static func push(_ context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        // AppKit thickens glyphs ("font smoothing") unless told not to; iOS
        // never does, and the video should weigh the same on both.
        context.setShouldSmoothFonts(false)
    }

    static func pop() { NSGraphicsContext.restoreGraphicsState() }
    static var currentContext: CGContext? { NSGraphicsContext.current?.cgContext }
}

extension NSFont {
    /// UIFont's line height: ascent, descent and leading. NSFont has no such
    /// property; this is the same sum UIKit reports.
    var lineHeight: CGFloat { ascender - descender + leading }
}

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        self.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    }

    func addLine(to point: CGPoint) { line(to: point) }

    /// UIKit's arc: radians, and `clockwise` as seen with y running down.
    /// AppKit takes degrees and reads `clockwise` with y running up, so the
    /// direction is inverted to sweep the same way in the flipped frame.
    func addArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat,
                clockwise: Bool) {
        appendArc(withCenter: center, radius: radius, startAngle: startAngle * 180 / .pi,
                  endAngle: endAngle * 180 / .pi, clockwise: !clockwise)
    }
}
#endif
