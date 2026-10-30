import SwiftUI

/// A small uppercase label inside a form row or above a group: «ES UNA DEVOLUCIÓN»,
/// «CADA MES». For the header of a `Section`, use `Text(…).ticketCaption()` instead.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.ink

    init(_ text: String, color: Color = Theme.ink) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.ticket(.detail))
            .tracking(Theme.Tracking.label)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// The quietest line: a hint under a field, and every section's footer. Wraps; never shrinks.
/// (`NoteText` is for a note inside the content, or a warning.)
struct HintText: View {
    let text: Text

    init(_ text: String) {
        self.text = Text(text)
    }

    /// For a footer with symbols in it: «★ ya viene elegida…».
    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.ticket(.hint))
            .tracking(Theme.Tracking.detail)
            .foregroundStyle(Theme.faint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A note under a field that explains (`detail`, `muted`), or warns (`danger`).
struct NoteText: View {
    let text: String
    var color: Color = Theme.muted

    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.ticket(.detail))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A form row led by a symbol: «💳 BBVA». The symbol's column grows with the text, so names
/// stay lined up at every text size; in accessibility sizes the row still fits because the
/// name wraps.
struct IconRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @ScaledMetric(relativeTo: .body) private var iconColumn = Theme.Size.iconColumn

    init(_ title: String, systemImage: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.brass)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            Text(title)
                .font(.ticket(.body))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Theme.Space.none)
            trailing()
        }
        .frame(minHeight: Theme.Size.tapTarget)
    }
}

extension IconRow where Trailing == EmptyView {
    init(_ title: String, systemImage: String) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

/// Lays its content out in a row, or in a column when the person uses an accessibility text
/// size and a row would cut words. The default answer to «this row breaks with large type».
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = Theme.Space.s
    var stackedSpacing: CGFloat = Theme.Space.xxs
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: stackedSpacing, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: spacing, content: content)
        }
    }
}

#Preview("Etiquetas y filas") {
    Form {
        Section {
            IconRow("BBVA", systemImage: "creditcard")
            IconRow("Despensa", systemImage: "cart") {
                Image(systemName: "star.fill").foregroundStyle(Theme.brass)
            }
            SectionLabel("Es una devolución")
            AdaptiveStack {
                Text("Hoy · 23 oct").font(.ticket(.microStrong)).foregroundStyle(Theme.brass)
                Text("$1,234.50").font(.ticket(.micro)).foregroundStyle(Theme.muted)
            }
        } header: {
            Text("Tarjetas").ticketCaption()
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HintText("Toca una para cambiarla o borrarla.")
                NoteText("Ya tienes uno con ese nombre.", color: Theme.danger)
            }
        }
        .listRowBackground(Theme.surface)
    }
    .ticketForm()
    .ticketPreview()
}
