import SwiftUI

/// The dashed edge of a blank ticket: the empty list, the budget still to set, a suggestion.
/// Put it in an `overlay`, or use `.ticketOutline()`.
struct TicketOutline: View {
    enum Weight {
        /// 1 pt: a small ticket inside a row.
        case regular
        /// 1.5 pt: a ticket that is the whole content (the empty list).
        case emphasis

        var lineWidth: CGFloat {
            switch self {
            case .regular: Theme.Stroke.hairline
            case .emphasis: Theme.Stroke.emphasis
            }
        }
    }

    var weight: Weight = .regular

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.ticket)
            .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: weight.lineWidth,
                                                            dash: Theme.Dash.ticket))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Draws a `TicketOutline` around the view.
    func ticketOutline(_ weight: TicketOutline.Weight = .regular) -> some View {
        overlay { TicketOutline(weight: weight) }
    }

    /// A quiet raised panel: `surface` fill with `Radius.panel` corners. Notes, previews.
    func ticketPanel() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    /// A choice drawn as a card: `surface` fill, `Radius.card` corners, a brass edge when chosen.
    /// The caller still adds `.accessibilityAddTraits(.isSelected)` when `selected`.
    func selectableCard(selected: Bool) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Theme.brass, lineWidth: Theme.Stroke.emphasis)
                }
            }
    }

    /// A small choice tile (a category, a symbol): brass when chosen, paper with a hairline
    /// edge when not.
    func choiceTile(selected: Bool) -> some View {
        background(selected ? Theme.brass : Theme.background,
                   in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                if !selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.hairline)
                }
            }
    }
}

#Preview("Formas") {
    VStack(alignment: .leading, spacing: Theme.Space.l) {
        Text("Sin gastos todavía").font(.ticket(.bodyStrong))
            .padding(Theme.Space.xlx)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ticketOutline(.emphasis)
        Text("Un aviso chico").font(.ticket(.detail)).foregroundStyle(Theme.muted)
            .padding(Theme.Space.ml)
            .ticketOutline()
        Text("Panel").font(.ticket(.detail)).foregroundStyle(Theme.ink)
            .padding(Theme.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .ticketPanel()
        Text("Pesos mexicanos").font(.ticket(.body)).foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.l)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow, alignment: .leading)
            .selectableCard(selected: true)
        HStack {
            Image(systemName: "cart").frame(maxWidth: .infinity, minHeight: Theme.Size.choiceTile)
                .foregroundStyle(Theme.onBrass).choiceTile(selected: true)
            Image(systemName: "fork.knife").frame(maxWidth: .infinity, minHeight: Theme.Size.choiceTile)
                .foregroundStyle(Theme.brass).choiceTile(selected: false)
        }
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
