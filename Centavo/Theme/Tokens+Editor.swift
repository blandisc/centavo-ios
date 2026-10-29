import SwiftUI

// Measures that only the expense editor and the swipe-to-delete row use.

extension Theme.Size {
    /// Narrowest a category or card button may be in the editor's adaptive grid.
    static let categoryGridMinimum: CGFloat = 96
    /// Scaled. Width of «Borrar» revealed by swiping a row.
    static let swipeButton: CGFloat = 84
}

extension Theme.Size {
    /// How small a category tile starts as it appears under «Ver más» (fraction of its size).
    static let tileAppear: CGFloat = 0.85
}

extension Theme.Motion {
    /// A category tile appearing under «Ver más»; `index` staggers them in reading order.
    static func tileIn(_ index: Int) -> Animation {
        .smooth(duration: 0.3).delay(0.04 * Double(max(index, 0)))
    }
}

