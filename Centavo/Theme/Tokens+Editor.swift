import SwiftUI

// Measures that only the expense editor and the swipe-to-delete row use.

extension Theme.Size {
    /// Narrowest a category or card button may be in the editor's adaptive grid.
    static let categoryGridMinimum: CGFloat = 96
    /// Scaled. Width of «Borrar» revealed by swiping a row.
    static let swipeButton: CGFloat = 84
}
