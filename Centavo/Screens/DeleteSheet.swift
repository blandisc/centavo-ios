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
    @State private var height: CGFloat = 320

    private var details: String {
        [expense.category, expense.card, expense.date.formatted(.dateTime.day().month(.abbreviated))]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("¿Borrar este gasto?")
                .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 20)

            VStack(spacing: 6) {
                Text(ledgerAmount(for: expense, primary: primaryCurrency))
                    .font(.ticket(32, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text(expense.shownName)
                    .font(.ticket(15, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !details.isEmpty {
                    Text(details)
                        .font(.ticket(12, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .overlay(alignment: .top) { Perforation() }
            .overlay(alignment: .bottom) { Perforation() }
            .accessibilityElement(children: .combine)

            Text(undoable ? "Podrás deshacerlo unos segundos." : "No se puede deshacer.")
                .font(.ticket(12, relativeTo: .footnote))
                .foregroundStyle(Theme.faint)
                .padding(.top, 14)
                .padding(.bottom, 20)

            VStack(spacing: 4) {
                Button {
                    confirm()
                    dismiss()
                } label: {
                    Text("Borrar")
                        .font(.ticket(15, weight: .semibold, relativeTo: .body))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .modifier(DangerCapsule())

                Button { dismiss() } label: {
                    Text("Conservar")
                        .font(.ticket(15, relativeTo: .body))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        // As tall as what it holds, at any text size.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
    }
}

/// The prominent button, in the one red the app has.
private struct DangerCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent).tint(Theme.danger)
        } else {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Theme.danger)
        }
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
