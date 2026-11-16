import SwiftUI

/// Lays its subviews out left to right and starts a new line when the next one
/// won't fit, like words in a paragraph.
///
/// Built for the sound panel's preset chips, which have to fit a phone sheet, a
/// popover and the narrow docked column on a landscape iPad alike.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    /// Which subviews go on which line, by index. Split out so the wrapping
    /// rule can be tested without rendering anything.
    ///
    /// A subview wider than the line still gets a line of its own; it's
    /// proposed the full width when placed, so a long name can wrap or clip
    /// there rather than disappear.
    static func lines(for sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (i, size) in sizes.enumerated() {
            let needed = current.isEmpty ? size.width : used + spacing + size.width
            if !current.isEmpty && needed > width {
                lines.append(current)
                current = [i]
                used = size.width
            } else {
                current.append(i)
                used = needed
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let sizes = measure(subviews, width: width)
        let lines = Self.lines(for: sizes, width: width, spacing: spacing)
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (n, line) in lines.enumerated() {
            height += lineHeight(line, sizes) + (n > 0 ? lineSpacing : 0)
            widest = max(widest, lineWidth(line, sizes))
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(subviews, width: bounds.width)
        var y = bounds.minY
        for line in Self.lines(for: sizes, width: bounds.width, spacing: spacing) {
            let height = lineHeight(line, sizes)
            var x = bounds.minX
            for i in line {
                subviews[i].place(at: CGPoint(x: x, y: y + (height - sizes[i].height) / 2),
                                  proposal: ProposedViewSize(sizes[i]))
                x += sizes[i].width + spacing
            }
            y += height + lineSpacing
        }
    }

    /// Ideal sizes, capped at the line width so one long subview can't push
    /// the layout wider than it was offered.
    private func measure(_ subviews: Subviews, width: CGFloat) -> [CGSize] {
        subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            guard ideal.width > width, width.isFinite else { return ideal }
            return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
    }

    private func lineHeight(_ line: [Int], _ sizes: [CGSize]) -> CGFloat {
        line.map { sizes[$0].height }.max() ?? 0
    }

    private func lineWidth(_ line: [Int], _ sizes: [CGSize]) -> CGFloat {
        line.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(line.count - 1, 0))
    }
}
