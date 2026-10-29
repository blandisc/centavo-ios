import SwiftUI

// Measures of the step-by-step flows: the first-time welcome (OnboardingView) and the Wallet
// setup guide (SetupGuideView), with the floating guide that follows the person into Atajos
// (GuideCompanion). Pages are scrolled, so nothing here is a fixed height; sizes are the
// *base* of an `@ScaledMetric`, growing with the pencil of the person who sets a big text size.

extension Theme.Size {
    /// Scaled. Side of the brass emblem tile that heads each step page (welcome and guide).
    /// About one title line tall: short titles («Conecta el importe») still fit on one line
    /// on an iPhone 17 Pro at the default text size, with `Theme.Space.m` beside them.
    static let stepEmblem: CGFloat = 44
    /// How far above its place the Wallet notice of the welcome's demo starts, before it drops.
    static let noticeDrop: CGFloat = 36
    /// How small the notice gets as it folds into the list (fraction of its size).
    static let noticeFold: CGFloat = 0.6
    /// How far below its place a block of an onboarding page starts, before it rises in.
    static let entranceRise: CGFloat = 14
    /// Scaled. A node of the «pagas → Atajos → Al día» chain on the welcome's Wallet page.
    static let chainNode: CGFloat = 52
    /// Height of the brass line that runs between two nodes of that chain.
    static let chainLink: CGFloat = 2
    /// The floating guide's card, in points (rendered at `companionScale`): a portrait 3:4
    /// picture, big enough type that it still reads in the small Picture in Picture window.
    static let companionCard = CGSize(width: 360, height: 480)
    /// Pixels per point of the floating guide's card.
    static let companionScale: CGFloat = 2
    /// Scaled. Width and height of the floating guide's thumbnail on a guide step (3:4).
    static let companionThumbWidth: CGFloat = 66
    static let companionThumbHeight: CGFloat = 88
    /// The most height the floating guide's instruction may take; past it the instruction
    /// steps down a size instead of being cut, and the screenshot takes whatever is left.
    static let companionTextBudget: CGFloat = 196
    /// Height of the floating guide's progress bar: one segment per guide step.
    static let companionProgress: CGFloat = 5
}

extension Theme.Symbol {
    /// The floating guide's stage when a picture has no screenshot: the step's symbol, big.
    static let companionStage: Font = .system(size: 72, weight: .light)
}

extension Theme {
    /// Type of the floating guide's pictures. They are read in a window a third of the screen
    /// wide (about 0.36×), so everything is drawn bigger than on a screen, and the card pins
    /// the text size: these are fixed sizes for a picture, not roles that grow.
    enum Companion {
        /// The instruction, largest first: the card takes the biggest one that fits
        /// `Theme.Size.companionTextBudget`, so a long instruction is never cut.
        static let instruction: [Font] = [
            .ticket(28, weight: .semibold, relativeTo: .title),
            .ticket(24, weight: .semibold, relativeTo: .title2),
            .ticket(21, weight: .semibold, relativeTo: .title3),
            .ticket(19, weight: .semibold, relativeTo: .title3),
        ]
        /// «PASO 3 DE 8», in brass.
        static let stepNumber: Font = .ticket(15, weight: .semibold, relativeTo: .footnote)
        /// The step's title under it.
        static let stepTitle: Font = .ticket(18, weight: .medium, relativeTo: .body)
        /// «ASÍ DEBE VERSE», the tag of a result picture.
        static let tag: Font = .ticket(16, weight: .semibold, relativeTo: .footnote)
    }
}

extension Theme.Opacity {
    /// 0.15: a brass wash behind a node that is lit.
    static let wash: Double = 0.15
}

extension Theme.Motion {
    /// The welcome: blocks rising in one after the other, and the demo of a payment arriving.
    enum Onboarding {
        /// One block of a page rising in; `index` staggers them top to bottom.
        static func rise(_ index: Int) -> Animation {
            .smooth(duration: 0.5).delay(0.08 + Double(index) * 0.07)
        }
        /// The Wallet notice dropping in from the top of the demo.
        static let noticeIn: Animation = .spring(duration: 0.5, bounce: 0.25)
        /// The notice folding into the list as a new row, and the figure going down.
        static let land: Animation = .spring(duration: 0.55, bounce: 0.15)
        /// A node of the Wallet chain lighting up.
        static let light: Animation = .easeOut(duration: 0.35)
        /// Pauses of the demo loop, in seconds: before the notice, while it shows, after it lands.
        static let beforeNotice: Double = 0.9
        static let noticeShown: Double = 1.4
        static let afterLanding: Double = 2.2
        /// Seconds each node of the Wallet chain stays lit.
        static let chainBeat: Double = 0.9
    }

    /// The floating guide: seconds each picture stays when it plays by itself.
    static let companionPage: Double = 8
    /// Half a second into a picture: where a skip lands, clear of the frame before it.
    static let companionSettle: Double = 0.5
    /// A jump of the player longer than this is the window's ⏩ / ⏪, not playing along.
    static let companionJump: Double = 3
    /// Seconds the floating guide's video takes to fade one picture into the next; it ends
    /// as the next picture starts, so a skip (at `companionSettle`) lands on a clean picture.
    static let companionFade: Double = 0.4
    /// In-between frames of that fade.
    static let companionFadeSteps = 8
    /// Seconds to wait for the window before opening Atajos without it.
    static let companionFallback: Double = 1.2
}
