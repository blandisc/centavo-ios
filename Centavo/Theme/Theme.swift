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
    /// Text on a brass fill.
    static var onBrass: Color { Color(hex: 0x131211) }
    /// The one destructive action: deleting an expense. 6:1 on `background`.
    static var danger: Color { Color(hex: 0xD9695A) }

    static let horizontalPadding: CGFloat = 24
}

/// A dashed perforation line, drawn at the top of whatever it is attached to.
struct Perforation: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(
                Line().stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
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
                    .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                    .tracking(2)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}
