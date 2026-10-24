import SwiftUI

// Measures of the step-by-step flows: the first-time welcome (OnboardingView) and the Wallet
// setup guide (SetupGuideView). Pages are scrolled, so nothing here is a fixed height; sizes
// are the *base* of an `@ScaledMetric`, growing with the pencil of the person who sets a big
// text size.

extension Theme.Size {
    /// Scaled. Side of the brass emblem tile that heads each step page (welcome and guide).
    /// About one title line tall: short titles («Conecta el importe») still fit on one line
    /// on an iPhone 17 Pro at the default text size, with `Theme.Space.m` beside them.
    static let stepEmblem: CGFloat = 44
}
