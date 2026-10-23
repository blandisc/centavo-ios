import SwiftUI

// Measures of the first-time welcome (OnboardingView). Pages are scrolled, so nothing here is
// a fixed height; sizes are the *base* of an `@ScaledMetric`, growing with the pencil of the
// person who sets a big text size.

extension Theme.Size {
    /// Scaled. Side of the brass emblem tile that heads each welcome page.
    static let onboardingEmblem: CGFloat = 52
}