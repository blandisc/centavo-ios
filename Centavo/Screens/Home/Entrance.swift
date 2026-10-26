import SwiftUI

/// What the main screen's entrance (the hero figure counting up, the month bar drawing itself)
/// has already played since the app opened.
///
/// The list the hero and the carousel sit in builds its rows lazily, so scrolling away and back
/// (or searching and coming back) rebuilds them, and a rebuilt view starts from zero and played
/// its entrance again. They read and write it here instead: the entrance plays when the app
/// opens, and never again.
@MainActor
final class Entrance {
    /// The figure «Hoy puedes gastar» last counted to.
    var heroFigure: Double = 0
    /// Whether the month bar has drawn itself.
    var barShown = false
    /// The bar's width once measured, so a rebuilt bar is the right size from its first frame
    /// instead of growing to it.
    var barWidth: CGFloat = 0
}
