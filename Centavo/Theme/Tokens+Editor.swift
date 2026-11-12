import SwiftUI

// Measures of the expense editor (its grid is also the one of «Pagos y categorías») and of the
// swipe-to-delete row.

extension Theme.Size {
    /// Narrowest a category or card tile may be in an adaptive grid: three across on an iPhone,
    /// in the expense sheet and in «Pagos y categorías» alike.
    static let categoryGridMinimum: CGFloat = 96
    /// Scaled. Width of «Borrar» revealed by swiping a row.
    static let swipeButton: CGFloat = 84
}
