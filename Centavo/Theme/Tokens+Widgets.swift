import SwiftUI
import WidgetKit

// Values of the widgets (CentavoWidgets/). A widget has a fixed size the system gives it, so its
// type is sized for that box, smaller than the app's, and it shrinks a little before it cuts.

/// Every text role of the widgets: `.font(.widget(.caption))`. Points at the default text size.
enum WidgetTextStyle {
    /// 38 medium. The big figure of the medium widget.
    case figureLarge
    /// 36 medium. The big figure of the small widget.
    case figure
    /// 32 medium. The big figure beside «En qué se va».
    case figureCompact
    /// 22 semibold. The figure of the lock screen's rectangle. Tracking `.figure`.
    case lockFigure
    /// 15 semibold. The figure inside the lock screen's ring.
    case ringFigure
    /// 12 medium. «Llevas $X» under the small widget's bar.
    case spent
    /// 11 regular. «Vas $376 abajo» under the figure.
    case verdict
    /// 10 regular. A short note in place of a chart («Sin categorías este mes»).
    case note
    /// 10 semibold. Captions in tracked capitals. Tracking `.widgetCaption`.
    case caption
    /// 9 semibold. A caption with less room (lock screen, «Fijar presupuesto»).
    case captionSmall
    /// 8 semibold. The smallest caption (under «Fijar presupuesto», the ring's «hoy»).
    case captionTiny
    /// 9 regular. Keys under the bar and the rows of «En qué se va».
    case key

    var size: CGFloat {
        switch self {
        case .figureLarge: 38
        case .figure: 36
        case .figureCompact: 32
        case .lockFigure: 22
        case .ringFigure: 15
        case .spent: 12
        case .verdict: 11
        case .note, .caption: 10
        case .captionSmall, .key: 9
        case .captionTiny: 8
        }
    }

    var weight: Font.Weight {
        switch self {
        case .figureLarge, .figure, .figureCompact, .spent: .medium
        case .lockFigure, .ringFigure, .caption, .captionSmall, .captionTiny: .semibold
        case .verdict, .note, .key: .regular
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .figureLarge, .figure, .figureCompact: .largeTitle
        case .lockFigure: .title2
        case .ringFigure: .body
        case .spent, .verdict: .footnote
        case .note: .caption
        case .caption, .captionSmall, .captionTiny, .key: .caption2
        }
    }
}

extension Font {
    /// The ticket typeface in one of the widgets' roles.
    static func widget(_ style: WidgetTextStyle) -> Font {
        TicketFont.font(size: style.size, weight: style.weight, relativeTo: style.textStyle)
    }
}

extension Theme.Symbol {
    /// The widget's «+».
    static let widgetAdd: Font = .system(size: 17, weight: .bold)
}

extension Theme.Size {
    /// The widget's «+» button.
    static let widgetAddButton: CGFloat = 36
    /// The month strip of the small widgets.
    static let widgetStrip: CGFloat = 8
    /// The month strip of the medium widget, with a tile per day.
    static let widgetStripTall: CGFloat = 12
    /// The month strip of the lock screen and the split bar of «En qué se va».
    static let widgetStripThin: CGFloat = 6
    /// Gap between the pieces of a strip; also the narrowest a piece may be drawn.
    static let widgetStripGap: CGFloat = 2
    /// How much taller than the strip the «Podrías llevar» rule is, in all.
    static let widgetMarkExtra: CGFloat = 4
    /// Half of `todayMarkWidth`: centers the rule on its x.
    static let widgetMarkHalf: CGFloat = 1
    /// The longest month: the most day tiles a strip draws.
    static let widgetMaxDays = 31
    /// The colored square of a key.
    static let widgetKeySquare: CGFloat = 7
    /// Least width of the percent column of «En qué se va».
    static let widgetPercentColumn: CGFloat = 26
    /// Height of the «Podrías llevar» line over the medium strip.
    static let widgetAnnotation: CGFloat = 12
    /// How far «Podrías llevar» stops short of its rule.
    static let widgetAnnotationInset: CGFloat = 2
    /// The dashed divider between «Hoy» and «En qué se va».
    static let widgetDivider: CGFloat = 1
}

extension Theme.Space {
    /// 1: lines of the lock screen's rectangle.
    static let widgetHair: CGFloat = 1
    /// 3: «Fijar presupuesto» and its subtitle.
    static let widgetCaptionGap: CGFloat = 3
    /// 5: rows of «En qué se va».
    static let widgetRowGap: CGFloat = 5
    /// The «$» of the widget's figure carries its own air: pulled back to line up.
    static let widgetOutset: CGFloat = -2
}

extension Theme.Radius {
    /// A day tile or a key square.
    static let widgetTile: CGFloat = 1.5
}

extension Theme.Dash {
    /// The fixed expenses still to come on the strip.
    static let widgetReserved: [CGFloat] = [2, 1.5]
    /// «Fijar presupuesto», the blank ticket in small.
    static let widgetTicket: [CGFloat] = [4, 3]
}

extension Theme.Tracking {
    /// The widgets' captions.
    static let widgetCaption: CGFloat = 1.3
    /// The widgets' big figure.
    static let widgetFigure: CGFloat = -1
}

extension Theme.MinimumScale {
    /// «Llevas $X» under the small widget's bar.
    static let widgetLabel: CGFloat = 0.8
    /// The rows of «En qué se va».
    static let widgetRow: CGFloat = 0.7
    /// The lock screen's figure.
    static let lockFigure: CGFloat = 0.5
    /// The widgets' big figure.
    static let widgetFigure: CGFloat = 0.45
    /// The figure inside the lock screen's ring.
    static let ringFigure: CGFloat = 0.4
}

extension Theme.Opacity {
    /// Today's tile on the medium strip.
    static let widgetToday: Double = 0.45
    /// The ring's «hoy» and the lock screen's captions.
    static let widgetSecondary: Double = 0.8
}

/// Colors that hold in every rendering mode: the app's own in full color, and the system's
/// one tone with opacities when iOS tints the widget, makes it clear or puts it on the
/// lock screen (the shape still says what each piece is).
struct Ink {
    let mode: WidgetRenderingMode
    var full: Bool { mode == .fullColor }

    var primary: Color { full ? Theme.ink : .primary }
    var muted: Color { full ? Theme.muted : .primary.opacity(0.7) }
    var brass: Color { full ? Theme.brass : .primary }
    var good: Color { full ? Theme.good : .primary }
    var danger: Color { full ? Theme.danger : .primary }
    var track: Color { full ? Theme.raised : .primary.opacity(0.22) }
    var reserved: Color { full ? Theme.brassLow : .primary.opacity(0.55) }
    var hairline: Color { full ? Theme.hairline : .primary.opacity(0.3) }
    /// The blank ticket's dashed border.
    var outline: Color { full ? Theme.outline : .primary.opacity(0.5) }
    /// The «+» on its circle.
    var onAdd: Color { full ? Theme.onBrass : .primary }
    var addBackground: Color { full ? Theme.brass : .primary.opacity(0.2) }
    /// A caption on the lock screen, one step under the figure.
    var lockCaption: Color { .primary.opacity(Theme.Opacity.widgetSecondary) }

    /// The `index`-th category of «En qué se va»: the app's colors, or the one tone fading.
    func category(_ index: Int, isRest: Bool) -> Color {
        guard full else { return .primary.opacity([1, 0.75, 0.5, 0.3][min(index, 3)]) }
        return isRest ? Theme.categoryRest : Theme.categories[min(index, Theme.categories.count - 1)]
    }
}
