import SwiftUI

/// «¿Borrar este gasto?» as a small ticket that rises from the bottom, under the thumb, with
/// the expense it is about. The system's dialog popped up at the top of the screen in iOS 26,
/// far from the swipe or the button that asked for it, in grey that is not the app's.
private struct DeleteSheet: View {
    let expense: Expense
    let primaryCurrency: String
    /// Whether «Deshacer» shows up after: the list keeps the expense a few seconds.
    let undoable: Bool
    let confirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 320 // ds-allow: altura inicial antes de medir el contenido

    private var details: String {
        [expense.category, expense.card, expense.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_MX")))]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: Theme.Space.none) {
            // Ink like every other sheet's title.
            Text("¿Borrar este gasto?")
                .font(.ticket(.footnoteStrong))
                .tracking(Theme.Tracking.title)
                .textCase(.uppercase)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Theme.Space.xl)

            VStack(spacing: Theme.Space.xs) {
                Text(ledgerAmount(for: expense, primary: primaryCurrency))
                    .font(.ticket(.display))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                // Written as in the list, so it reads as the same expense.
                Text(expense.shownName)
                    .font(.ticket(.bodyMedium))
                    .tracking(Theme.Tracking.name)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !details.isEmpty {
                    Text(details)
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.lx)
            .overlay(alignment: .top) { Perforation() }
            .overlay(alignment: .bottom) { Perforation() }
            .accessibilityElement(children: .combine)

            Text(undoable ? "Podrás deshacerlo unos segundos." : "No se puede deshacer.")
                .font(.ticket(.detail))
                .foregroundStyle(Theme.faint)
                .padding(.top, Theme.Space.ml)
                .padding(.bottom, Theme.Space.xl)

            VStack(spacing: Theme.Space.xxs) {
                Button {
                    confirm()
                    dismiss()
                } label: {
                    Text("Borrar")
                        .font(.ticket(.bodyStrong))
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.wideCapsuleLabel)
                }
                .ticketProminent(.destructive)

                Button { dismiss() } label: {
                    Text("Conservar")
                        .font(.ticket(.body))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, Theme.Space.xxxl)
        .padding(.bottom, Theme.Space.s)
        .fixedSize(horizontal: false, vertical: true)
        // As tall as what it holds, at any text size.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(Theme.Radius.sheet)
    }
}

extension View {
    /// Asks before deleting `expense` with `DeleteSheet`; `nil` closes it.
    func confirmsDelete(of expense: Binding<Expense?>, primaryCurrency: String,
                        undoable: Bool, onDelete: @escaping (Expense) -> Void) -> some View {
        modifier(ConfirmsDelete(expense: expense, primaryCurrency: primaryCurrency,
                                undoable: undoable, onDelete: onDelete))
    }
}

private struct ConfirmsDelete: ViewModifier {
    @Binding var expense: Expense?
    let primaryCurrency: String
    let undoable: Bool
    let onDelete: (Expense) -> Void
    @State private var confirmed: Expense?

    func body(content: Content) -> some View {
        // Deleted once the sheet is gone: the sheet still draws the expense while it slides
        // down, and a deleted SwiftData object can't be read.
        content.sheet(item: $expense, onDismiss: {
            if let confirmed { onDelete(confirmed) }
            confirmed = nil
        }) { item in
            DeleteSheet(expense: item, primaryCurrency: primaryCurrency, undoable: undoable) {
                confirmed = item
            }
        }
    }
}
