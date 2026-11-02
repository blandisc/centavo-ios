import SwiftUI

// Measures that only the expense editor and the swipe-to-delete row use.

extension Theme.Size {
    /// Narrowest a category or card button may be in the editor's adaptive grid.
    static let categoryGridMinimum: CGFloat = 96
    /// Scaled. Width of «Borrar» revealed by swiping a row.
    static let swipeButton: CGFloat = 84
}

extension Theme.Motion {
    /// One of the categories under «Ver más» showing: each once the room opening downward
    /// (`fold`) has reached about where it sits, so they appear top to bottom and never draw
    /// over the button.
    static func tileIn(_ index: Int, of count: Int) -> Animation {
        let reached = foldSeconds * Double(index + 1) / Double(max(count, 1))
        return .easeOut(duration: 0.22).delay(max(.zero, reached - 0.12))
    }
}
