import SwiftUI

// Measures of the step-by-step flows: the first-time welcome (OnboardingView) and the Wallet
// setup guide (SetupGuideView). Pages are scrolled, so nothing here is a fixed height; sizes
// are the *base* of an `@ScaledMetric`, growing with the pencil of the person who sets a big
// text size.

extension Theme.Size {
    /// Scaled. Side of the brass emblem tile that heads each step page (welcome and guide).
    static let stepEmblem: CGFloat = 52
}
