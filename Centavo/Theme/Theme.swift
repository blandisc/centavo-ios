import SwiftUI

extension Color {
    /// `Color(hex: 0xD0A44E)`. sRGB, opaque.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The "Noche ticket" look: warm near-black paper, one brass accent, receipt type.
/// Every value comes from the approved sketches (see docs/DECISIONS.md).
enum Theme {
    static var background: Color { Color(hex: 0x131211) }
    /// Slightly lifted fill for empty calendar days and fields.
    static var surface: Color { Color(hex: 0x1F1E1C) }
    /// One step above `surface`: the days still to come in the month's bar.
    static var raised: Color { Color(hex: 0x2C2A27) }
    static var ink: Color { Color(hex: 0xEDEAE4) }
    /// Secondary text. 6.5:1 on `background`.
    static var muted: Color { Color(hex: 0x9C978D) }
    /// Quietest text: future calendar days, placeholders, hints. 5.2:1 on `background`,
    /// 4.6:1 on `surface`: still readable, because Apple's audit failed the dimmer grey.
    static var faint: Color { Color(hex: 0x8A867D) }
    static var brass: Color { Color(hex: 0xD0A44E) }
    static var brassMid: Color { Color(hex: 0x9A7A3E) }
    static var brassLow: Color { Color(hex: 0x5E4D2B) }
    /// Dashed rules between rows, the perforation of the ticket.
    static var hairline: Color { Color(hex: 0x2E2C29) }
    /// Dashed outline of a blank ticket (the budget, the empty state). A line, not text, so
    /// the 3:1 that graphics need is enough.
    static var outline: Color { Color(hex: 0x6E6A62) }
    /// Something present but not current, like the carousel's other page dot.
    static var dimmed: Color { Color(hex: 0x4A4742) }
    /// Text on a brass fill.
    static var onBrass: Color { Color(hex: 0x131211) }
    /// The one destructive action: deleting an expense. 6:1 on `background`.
    static var danger: Color { Color(hex: 0xD9695A) }
    /// «Vas bien»: under what an even month would have spent. 7:1 on `background`.
    static var good: Color { Color(hex: 0x8DBF86) }

    /// One fixed color per category and per way of paying (`ColorTags`, 2026-10-29), the same
    /// in the list, «En qué se va», «Pagos y categorías» and the widget. Eight, all readable
    /// on `background`; with more names than colors some repeat, which is why the name is
    /// always written beside it. The order is the order the color row shows them.
    static let categories: [Color] = [Color(hex: 0xC2861F), Color(hex: 0x1E9C73),
                                      Color(hex: 0x4C86D9), Color(hex: 0xE07A9A),
                                      Color(hex: 0x9B7FE0), Color(hex: 0x2BB3C0),
                                      Color(hex: 0xE0743F), Color(hex: 0xA6B04A)]
    /// What VoiceOver and the color menu call each of `categories`, in the same order.
    static let categoryColorNames = ["Ocre", "Verde", "Azul", "Rosa", "Violeta", "Turquesa", "Coral", "Oliva"]
    /// «Otras», everything past the four: grey, so it never reads as a category of its own.
    static var categoryRest: Color { Color(hex: 0x6E6A62) }

    static let horizontalPadding: CGFloat = 24

    /// The setup guide draws Apple's Shortcuts app (dark mode) so each step looks like the
    /// screen the person will see there. Only for those drawings, never for Centavo itself.
    enum Shortcuts {
        static var screen: Color { Color(hex: 0x1C1C1E) }
        static var card: Color { Color(hex: 0x2C2C2E) }
        static var text: Color { Color(hex: 0xFFFFFF) }
        static var secondary: Color { Color(hex: 0x98989F) }
        /// iOS's dark-mode blue: placeholders and variables in an action.
        static var blue: Color { Color(hex: 0x0A84FF) }
    }
}

/// A dashed perforation line, drawn at the top of whatever it is attached to.
struct Perforation: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: Theme.Stroke.hairline)
            .overlay(
                Line().stroke(Theme.hairline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                                 dash: Theme.Dash.perforation))
            )
            .accessibilityHidden(true)
    }

    /// Starts and ends on a dash, centered, so the line is as far from both edges.
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            let dash = Theme.Dash.perforation.first ?? 0
            let period = Theme.Dash.perforation.reduce(0, +)
            let drawn = period > 0 ? max(((rect.width + period - dash) / period).rounded(.down) * period - (period - dash), 0)
                : rect.width
            let start = rect.minX + (rect.width - drawn) / 2
            var path = Path()
            path.move(to: CGPoint(x: start, y: rect.midY))
            path.addLine(to: CGPoint(x: start + drawn, y: rect.midY))
            return path
        }
    }
}

extension View {
    /// A native `Form`/`List` dressed as the ticket: dark paper, no system grey.
    func ticketForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .presentationBackground(Theme.background)
    }

    /// The small spaced title in a sheet's navigation bar: "NUEVO GASTO".
    func ticketBarTitle(_ title: String) -> some View {
        self.toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.ticket(.footnoteStrong))
                    .tracking(Theme.Tracking.title)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}
