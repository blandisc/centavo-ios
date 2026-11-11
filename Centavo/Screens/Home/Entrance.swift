import SwiftUI

/// What the main screen's entrance (the hero figure counting up, the boleto and its line coming
/// in) has already played since the app opened.
///
/// The list the hero and the carousel sit in builds its rows lazily, so scrolling away and back
/// (or searching and coming back) rebuilds them, and a rebuilt view starts from zero and played
/// its entrance again. They read and write it here instead: the entrance plays when the app
/// opens, and never again.
@MainActor
final class Entrance {
    /// The figure «Hoy puedes gastar» last counted to.
    var heroFigure: Double = 0
    /// Whether the boleto and the line under it have come in.
    var barShown = false
}
