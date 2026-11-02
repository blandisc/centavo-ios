import SwiftUI

// Measures of «Cómo funciona» (TutorialView, 2026-11-01): stories that move on by themselves,
// each with a drawing that plays once and stays still. How long a story stays is CentavoCore's
// `StoryTiming` (it depends on how much there is to read), not a token.

extension Theme.Size {
    /// Height of a story's drawing.
    static let tutorialArt: CGFloat = 220
    /// Height of each part of the progress bar along the top.
    static let tutorialProgress: CGFloat = 3
    /// How far down a drag must go to close the stories.
    static let tutorialCloseDrag: CGFloat = 80
    /// Less movement than this is a tap, not a drag.
    static let tutorialTapSlop: CGFloat = 10
    /// The share of the width, from the leading edge, that goes back instead of forward.
    static let tutorialBackShare: CGFloat = 0.3
}

extension Theme.Motion {
    enum Tutorial {
        /// How long a story's drawing plays before it stays still.
        static let draw: Double = 2.4
        /// How often the clock checks again while a story is held (seconds).
        static let tick: Double = 0.05
        /// The progress bar filling the rest of the story, evenly.
        static func fill(seconds: Double) -> Animation { .linear(duration: seconds) }
        /// Pressing longer than this holds the story instead of moving on.
        static let hold: Double = 0.25
        /// One story into the next: a crossfade, no slide.
        static let change: Animation = .smooth(duration: 0.35)
        /// The old story's words fade out fast…
        static let leave: Animation = .easeOut(duration: 0.12)
        /// …and the new ones fade in once they are gone, so the two never overlap.
        static let arrive: Animation = .easeOut(duration: 0.25).delay(0.12)
    }
}

extension AnyTransition {
    /// One story into the next (`TutorialView`): out first, then in; never both at once.
    static var storyChange: AnyTransition {
        .asymmetric(insertion: .opacity.animation(Theme.Motion.Tutorial.arrive),
                    removal: .opacity.animation(Theme.Motion.Tutorial.leave))
    }
}
