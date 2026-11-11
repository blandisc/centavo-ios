import SwiftUI

/// What the app asks before something goes away for good: deleting an expense, stopping a fixed
/// expense, deleting a card or a category, throwing away what was typed. One way to ask, the
/// same everywhere (owner, 2026-11-11): a small ticket that rises from the bottom, under the
/// thumb, with what it is about, a red button with its verb and «Conservar».
///
/// For something that is not an expense (an account of «Mi dinero», say), with the thing in a
/// `@State private var removing: MoneyAccount?` (any `Identifiable`):
///
///     .confirmsRemoval(of: $removing, question: { account in
///         TicketQuestion(title: "¿Quitar esta cuenta?",
///                        name: account.name,                      // drawn as «BBVA NÓMINA»
///                        detail: "Ahorro · $12,400.00",           // optional, under the name
///                        note: "Los cortes pasados la conservan.", // optional, under the ticket
///                        verb: "Quitar")                          // «Borrar» if left out
///     }) { account in
///         remove(account)   // runs once the question is gone, only after the red button
///     }
///
/// With a flag instead of an item: `.confirmsRemoval(isPresented: $asking, question: { … }) { … }`.
/// Leave every optional out and only the title, the note and the two buttons show.
/// Expenses keep their own shorthand, `.confirmsDelete(of:primaryCurrency:undoable:onDelete:)`.
struct TicketQuestion {
    /// «¿Quitar este gasto fijo?»: drawn in capitals as the sheet's title.
    var title: String
    /// A figure over the name, as big as an expense's amount: «$1,200.00». Optional.
    var figure: String?
    /// What it is about, drawn between «» in capitals: pass it bare («Renta»). Optional.
    var name: String?
    /// One quiet line under the name: «Comida · BBVA · 3 nov», «12 gastos la tienen». Optional.
    var detail: String?
    /// What happens after, under the ticket: «No se puede deshacer.». Optional.
    var note: String?
    /// The red button: «Borrar», «Quitar», «Dejar de repetir», «Descartar».
    var verb = "Borrar"
    /// The quiet button that changes nothing: «Conservar», «Seguir editando».
    var keep = "Conservar"
    /// `false` only for an expense, whose name is written as in the list, without «».
    fileprivate var quotesName = true

    init(title: String, figure: String? = nil, name: String? = nil, detail: String? = nil,
         note: String? = nil, verb: String = "Borrar", keep: String = "Conservar") {
        self.title = title
        self.figure = figure
        self.name = name
        self.detail = detail
        self.note = note
        self.verb = verb
        self.keep = keep
    }

    /// «¿Borrar este gasto?», with the expense as the list writes it.
    fileprivate init(deleting expense: Expense, primaryCurrency: String, undoable: Bool) {
        let details = [expense.category, expense.card,
                       expense.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_MX")))]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        self.init(title: "¿Borrar este gasto?",
                  figure: ledgerAmount(for: expense, primary: primaryCurrency),
                  // Written as in the list, so it reads as the same expense.
                  name: expense.shownName,
                  detail: details.isEmpty ? nil : details,
                  note: undoable ? "Podrás deshacerlo unos segundos." : "No se puede deshacer.")
        quotesName = false
    }

    fileprivate var hasTicket: Bool { figure != nil || name != nil || detail != nil }
}

/// The question as a small ticket that rises from the bottom, under the thumb. The system's
/// dialog popped up at the top of the screen in iOS 26, far from the swipe or the button that
/// asked for it, in grey that is not the app's.
private struct TicketQuestionSheet: View {
    let question: TicketQuestion
    let confirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var height: CGFloat = 320 // ds-allow: altura inicial antes de medir el contenido

    var body: some View {
        if typeSize.isAccessibilitySize {
            // With the largest text it may not fit under the thumb: the whole sheet, scrolling,
            // so «Borrar» and «Conservar» are always reachable (audit 2026-11-02).
            ScrollView { ticket }
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
                .presentationCornerRadius(Theme.Radius.sheet)
        } else {
            ticket
                .fixedSize(horizontal: false, vertical: true)
                // As tall as what it holds.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .presentationDetents([.height(height)])
                .presentationBackground(Theme.background)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
    }

    private var ticket: some View {
        VStack(spacing: Theme.Space.none) {
            // Ink like every other sheet's title.
            Text(question.title)
                .font(.ticket(.footnoteStrong))
                .tracking(Theme.Tracking.title)
                .textCase(.uppercase)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Theme.Space.xl)

            if question.hasTicket {
                VStack(spacing: Theme.Space.xs) {
                    if let figure = question.figure {
                        Text(figure)
                            .font(.ticket(.display))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                    }
                    if let name = question.name {
                        Text(question.quotesName ? "«\(name)»" : name)
                            .font(.ticket(.bodyMedium))
                            .tracking(Theme.Tracking.name)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }
                    if let detail = question.detail {
                        Text(detail)
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
            }

            if let note = question.note {
                Text(note)
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.top, question.hasTicket ? Theme.Space.ml : Theme.Space.none)
                    .padding(.bottom, Theme.Space.xl)
            } else if question.hasTicket {
                // The same air over the buttons as with a note.
                Color.clear.frame(height: Theme.Space.xl)
            }

            VStack(spacing: Theme.Space.xxs) {
                Button {
                    confirm()
                    dismiss()
                } label: {
                    Text(question.verb)
                        .font(.ticket(.bodyStrong))
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.wideCapsuleLabel)
                }
                .ticketProminent(.destructive)

                Button { dismiss() } label: {
                    Text(question.keep)
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
    }
}

extension View {
    /// Asks before deleting `expense` with the ticket question; `nil` closes it.
    func confirmsDelete(of expense: Binding<Expense?>, primaryCurrency: String,
                        undoable: Bool, onDelete: @escaping (Expense) -> Void) -> some View {
        confirmsRemoval(of: expense, question: {
            TicketQuestion(deleting: $0, primaryCurrency: primaryCurrency, undoable: undoable)
        }, onConfirm: onDelete)
    }

    /// Asks `question` about `item` before `onConfirm` deletes, removes or stops it; `nil`
    /// closes the question. `onConfirm` runs once the question is gone, and only after the red
    /// button: «Conservar» or swiping it down change nothing. See `TicketQuestion` for an example.
    func confirmsRemoval<Item: Identifiable>(of item: Binding<Item?>,
                                             question: @escaping (Item) -> TicketQuestion,
                                             onConfirm: @escaping (Item) -> Void) -> some View {
        modifier(ConfirmsRemoval(item: item, question: question, onConfirm: onConfirm))
    }

    /// The same question for something that needs no item: a flag opens it.
    func confirmsRemoval(isPresented: Binding<Bool>, question: @escaping () -> TicketQuestion,
                         onConfirm: @escaping () -> Void) -> some View {
        confirmsRemoval(of: Binding<AskedOnce?>(get: { isPresented.wrappedValue ? AskedOnce() : nil },
                                                set: { if $0 == nil { isPresented.wrappedValue = false } }),
                        question: { _ in question() }, onConfirm: { _ in onConfirm() })
    }
}

/// What a question opened by a flag is about: always the same one.
private struct AskedOnce: Identifiable {
    let id = 0
}

private struct ConfirmsRemoval<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let question: (Item) -> TicketQuestion
    let onConfirm: (Item) -> Void
    @State private var confirmed: Item?

    func body(content: Content) -> some View {
        // Done once the sheet is gone: the sheet still draws the expense while it slides
        // down, and a deleted SwiftData object can't be read.
        content.sheet(item: $item, onDismiss: {
            if let confirmed { onConfirm(confirmed) }
            confirmed = nil
        }) { item in
            TicketQuestionSheet(question: question(item)) {
                confirmed = item
            }
        }
    }
}
