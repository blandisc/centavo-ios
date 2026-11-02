import SwiftUI

/// An adaptive grid (like `LazyVGrid` with `.adaptive(minimum:)`) that is only as tall as its
/// first `firstCount` items until it opens (2026-11-02): `open` goes from 0 to 1 and the room
/// grows downward between the two heights, with every item already in its final place, so
/// nothing in view moves. Animatable, worked out in the layout itself: nothing is measured
/// into state and fed back.
struct RevealGrid: Layout {
    var minimum: CGFloat
    var spacing: CGFloat
    var firstCount: Int
    var open: CGFloat

    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }

    private struct Plan {
        var columnWidth: CGFloat
        var columns: Int
        var rowHeights: [CGFloat]
        var collapsed: CGFloat
        var full: CGFloat
    }

    private func plan(width: CGFloat, subviews: Subviews) -> Plan {
        let columns = max(1, Int((width + spacing) / (minimum + spacing)))
        let columnWidth = max(.zero, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var rowHeights: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            if row == rowHeights.count { rowHeights.append(height) } else { rowHeights[row] = max(rowHeights[row], height) }
        }
        func height(rows: Int) -> CGFloat {
            let used = rowHeights.prefix(rows)
            return used.reduce(.zero, +) + spacing * CGFloat(max(used.count - 1, 0))
        }
        let firstRows = firstCount == 0 ? 0 : (min(firstCount, subviews.count) - 1) / columns + 1
        return Plan(columnWidth: columnWidth, columns: columns, rowHeights: rowHeights,
                    collapsed: height(rows: firstRows), full: height(rows: rowHeights.count))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimum
        let plan = plan(width: width, subviews: subviews)
        // `open` eases from 0 to 1 without overshoot (`Theme.Motion.fold`), so it needs no clamp.
        return CGSize(width: width, height: plan.collapsed + (plan.full - plan.collapsed) * open)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = plan(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, rowHeight) in plan.rowHeights.enumerated() {
            for column in 0..<plan.columns {
                let index = row * plan.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (plan.columnWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: plan.columnWidth, height: rowHeight))
            }
            y += rowHeight + spacing
        }
    }
}
