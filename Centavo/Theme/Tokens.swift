import SwiftUI

// The measured half of «Noche ticket»: every spacing, corner, size, line, opacity, letter
// spacing and timing a screen may use. Colors are in Theme.swift, type in TicketFont.swift.
//
// A screen never writes a number for any of these: `Tools/lint-design.sh` fails the build if
// it does. Need a value that is not here? Add it here, with a comment saying where it goes,
// in the same PR (see docs/DESIGN_SYSTEM.md). Values are points at the default text size;
// those that must grow with Dynamic Type are read through `@ScaledMetric` (see `Theme.Size`).

extension Theme {
    /// Gaps between and around things (`padding`, `spacing`). The ladder the approved sketches
    /// use; pick the step, never a number in between.
    enum Space {
        /// Glued: a title and the line right under it.
        static let none: CGFloat = 0
        /// 2 pt. Lines of one block (a merchant and its details).
        static let xxxs: CGFloat = 2
        /// 4 pt. A label and its value; stacked rows in large type.
        static let xxs: CGFloat = 4
        /// 6 pt. A caption and the text it heads.
        static let xs: CGFloat = 6
        /// 8 pt. Items of a row; the default small gap.
        static let s: CGFloat = 8
        /// 10 pt. Rows of a short list; a button bar's vertical padding.
        static let sm: CGFloat = 10
        /// 12 pt. Icon to text; elements of a card.
        static let m: CGFloat = 12
        /// 14 pt. Inside a blank ticket; between a block and its note.
        static let ml: CGFloat = 14
        /// 16 pt. Inside a card or a selectable row.
        static let l: CGFloat = 16
        /// 18 pt. Around the ticket in the delete sheet.
        static let lx: CGFloat = 18
        /// 20 pt. Between the blocks of a page.
        static let xl: CGFloat = 20
        /// 22 pt. Inside the empty-list ticket.
        static let xlx: CGFloat = 22
        /// 24 pt. Screen margin (same as `Theme.horizontalPadding`) and page top/bottom.
        static let xxl: CGFloat = 24
        /// 28 pt. Top of a sheet that has no navigation bar.
        static let xxxl: CGFloat = 28
        /// Left and right margin of every screen.
        static let screen: CGFloat = Theme.horizontalPadding
    }

    /// Corner radii. Receipts are almost square: small radii, never pill-shaped cards.
    enum Radius {
        /// 2 pt. A legend swatch.
        static let bar: CGFloat = 2
        /// 3 pt. The month bar, its segments and a pulsing tile.
        static let tile: CGFloat = 3
        /// 4 pt. A calendar day.
        static let chip: CGFloat = 4
        /// 6 pt. The dashed blank ticket (`TicketOutline`).
        static let ticket: CGFloat = 6
        /// 8 pt. Icon tiles, category buttons, small controls.
        static let control: CGFloat = 8
        /// 10 pt. Panels: a note box, the swipe button, the map preview.
        static let panel: CGFloat = 10
        /// 12 pt. Selectable cards (`SelectableCard`).
        static let card: CGFloat = 12
        /// 28 pt. Top corners of a sheet sized to its content.
        static let sheet: CGFloat = 28
    }

    /// Fixed sizes. The ones marked «scaled» are base values for an `@ScaledMetric`, never a
    /// plain `frame`: they must grow with the text next to them.
    enum Size {
        /// 44 pt: Apple's minimum tap target. Every button and tappable row is at least this.
        static let tapTarget: CGFloat = 44
        /// 28 pt: a row that is not tapped on its own (a status line inside a card).
        static let compactRow: CGFloat = 28
        /// 34 pt: label height inside a capsule button (the capsule adds the rest to 44).
        static let capsuleLabel: CGFloat = 34
        /// 36 pt: label height inside the full-width destructive button.
        static let wideCapsuleLabel: CGFloat = 36
        /// 48 pt: a symbol tile in a grid of choices.
        static let choiceTile: CGFloat = 48
        /// 52 pt: a list row with two lines; a selectable card.
        static let tallRow: CGFloat = 52
        /// 58 pt: a category button (symbol over name).
        static let categoryTile: CGFloat = 58

        /// Scaled. Width of the symbol column in a form row (`IconRow`).
        static let iconColumn: CGFloat = 28
        /// Scaled. Width of the symbol column next to body text (onboarding points).
        static let iconColumnNarrow: CGFloat = 22
        /// Scaled. Width of the symbol column for large symbols (`.title3`).
        static let iconColumnWide: CGFloat = 32
        /// Scaled. Side of the category tile in a list row.
        static let rowTile: CGFloat = 32
        /// Scaled. A symbol drawn inside `rowTile`.
        static let rowTileSymbol: CGFloat = 15
        /// Scaled. Height of the symbol box in a category button.
        static let categorySymbol: CGFloat = 22
        /// Scaled. A small status glyph before text.
        static let glyph: CGFloat = 14
        /// Scaled. A step number's column in the guide.
        static let stepNumber: CGFloat = 16

        /// The page dots of the carousel: idle and current widths, and their height.
        static let pageDot: CGFloat = 6
        static let pageDotCurrent: CGFloat = 18
        /// A legend dot next to a figure.
        static let legendDot: CGFloat = 8
        /// The short brass tick that starts a day in the list.
        static let dayTick = CGSize(width: 14, height: 3)
        /// The «today» mark across the month bar.
        static let todayMarkWidth: CGFloat = 2
        /// Preview height of the map in the expense sheet.
        static let mapPreview: CGFloat = 160
    }

    /// Sizes of SF Symbols, set with `.font(Theme.Symbol.large)`. Symbols follow the system's
    /// text styles so they grow with Dynamic Type next to the ticket type.
    enum Symbol {
        /// Next to body text: a category button.
        static let regular: Font = .body
        /// A symbol that is the content: the choices in «Nueva tarjeta».
        static let large: Font = .title3
    }

    /// Line widths.
    enum Stroke {
        /// 0.5 pt. Outline of a legend swatch.
        static let fine: CGFloat = 0.5
        /// 1 pt. Hairlines, perforations, a small blank ticket.
        static let hairline: CGFloat = 1
        /// 1.2 pt. The even-pace mark on the month bar.
        static let mark: CGFloat = 1.2
        /// 1.5 pt. Selection borders and the empty-list ticket.
        static let emphasis: CGFloat = 1.5
        /// 2 pt. A selection ring (today in the calendar, the chosen mosaic tile).
        static let strong: CGFloat = 2
    }

    /// Dash patterns for `StrokeStyle(dash:)`.
    enum Dash {
        /// The perforation between rows.
        static let perforation: [CGFloat] = [3, 3]
        /// The dashed edge of a blank ticket.
        static let ticket: [CGFloat] = [5, 4]
        /// The reserved part of the month bar (fixed expenses still to come).
        static let dotted: [CGFloat] = [3, 2]
    }

    /// Opacities. Only for marks and fills; text uses `ink`/`muted`/`faint`, never a faded ink.
    enum Opacity {
        /// Hidden, for entrance animations.
        static let hidden: Double = 0
        static let visible: Double = 1
        /// 0.25: the brass rule after a day's name.
        static let rule: Double = 0.25
        /// 0.35: the brass glow of a pulsing tile.
        static let glow: Double = 0.35
        /// 0.4: what is not selected while something else is.
        static let unselected: Double = 0.4
        /// 0.55 / 0.8: the even-pace mark when behind / ahead of it.
        static let paceBehind: Double = 0.55
        static let paceAhead: Double = 0.8
        /// 0.75: a secondary figure on a colored tile.
        static let onTileSecondary: Double = 0.75
    }

    /// Letter spacing for `.tracking(_:)`. Uppercase labels open up; big figures close in.
    enum Tracking {
        /// 0: the typeface's own spacing.
        static let none: CGFloat = 0
        /// −2: the hero figure.
        static let hero: CGFloat = -2
        /// −1.5: an amount being typed.
        static let amount: CGFloat = -1.5
        /// −0.5: a large figure inside a card.
        static let figure: CGFloat = -0.5
        /// 0.4: an uppercase merchant name.
        static let name: CGFloat = 0.4
        /// 0.6: hints, details and typed text.
        static let detail: CGFloat = 0.6
        /// 0.8: a label squeezed into a compact layout.
        static let compactLabel: CGFloat = 0.8
        /// 1: a short uppercase tag.
        static let tag: CGFloat = 1
        /// 1.2: uppercase section labels and button titles (`SectionLabel`).
        static let label: CGFloat = 1.2
        /// 1.4: uppercase actions (`TicketButtonStyle`, day dividers).
        static let action: CGFloat = 1.4
        /// 1.6: captions (`ticketCaption()`).
        static let caption: CGFloat = 1.6
        /// 2: the bar title of a sheet.
        static let title: CGFloat = 2
    }

    /// The smallest a line of text may shrink to fit (`minimumScaleFactor`). Text should wrap or
    /// stack instead (see docs/DESIGN_SYSTEM.md, Dynamic Type); this is the last resort.
    enum MinimumScale {
        /// Words: never smaller than three quarters of what the person asked for.
        static let text: CGFloat = 0.75
        /// A big figure on one line (the hero amount), where wrapping would split a number.
        static let figure: CGFloat = 0.6
    }

    /// Timings. Always go through `Theme.Motion.animation(_:reduceMotion:)` or check
    /// `accessibilityReduceMotion` yourself: with «Reducir movimiento» nothing slides.
    enum Motion {
        /// A tap's answer: selection, a filter, a small figure rolling.
        static let quick: Animation = .snappy
        /// A page changing.
        static let page: Animation = .snappy(duration: 0.3)
        /// A swipe settling, a dot sliding.
        static let settle: Animation = .smooth(duration: 0.3)
        /// A height easing to the next page.
        static let resize: Animation = .smooth(duration: 0.4)
        /// A layout changing style or size.
        static let restyle: Animation = .smooth(duration: 0.45)
        /// The hero figure counting up on open.
        static let countUp: Animation = .snappy(duration: 0.9)
        /// A slow breathing pulse (a tile asking to be looked at).
        static let pulse: Animation = .easeInOut(duration: 1.4)
        /// A tap that opens or closes a detail with a small bounce.
        static let toggle: Animation = .spring(duration: 0.45, bounce: 0.2)

        /// The month bar drawing itself when the screen opens, in order.
        enum Entrance {
            static let fill: Animation = .spring(duration: 0.9, bounce: 0.18).delay(0.1)
            static let refill: Animation = .spring(duration: 0.6, bounce: 0.15)
            static let markers: Animation = .easeOut(duration: 0.3).delay(0.5)
            /// One bar of the chart; `index` staggers them left to right.
            static func bar(_ index: Int) -> Animation {
                .spring(duration: 0.4, bounce: 0.3).delay(0.45 + Double(index) * 0.035)
            }
            static let today: Animation = .easeOut(duration: 0.35).delay(0.7)
            static let annotation: Animation = .easeOut(duration: 0.4).delay(0.75)
            static let pace: Animation = .easeOut(duration: 0.4).delay(0.8)
            static let legend: Animation = .easeOut(duration: 0.4).delay(0.9)
            /// Bars start this tall (fraction of their height) and grow to full.
            static let barStart: CGFloat = 0.3
        }

        /// `animation`, or none with «Reducir movimiento» on.
        static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }
}
