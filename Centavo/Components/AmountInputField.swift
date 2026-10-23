import CentavoCore
import SwiftUI

/// The big field where an amount is typed: decimal pad, thousands put in while typing,
/// receipt figures. The same in the expense sheet, the budget and the fixed expenses.
///
///     AmountInputField("Monto", text: $amountText, prompt: "0.00", identifier: "monto")
///         .focused($amountFocused)
struct AmountInputField: View {
    enum Size {
        /// 44 pt, tight tracking: the first row of a sheet's form.
        case regular
        /// 40 pt: inside a card, where 44 leaves no room (onboarding).
        case compact
    }

    let title: String
    @Binding var text: String
    var prompt: String = "0"
    var size: Size = .regular
    var identifier: String?

    init(_ title: String, text: Binding<String>, prompt: String = "0", size: Size = .regular,
         identifier: String? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.size = size
        self.identifier = identifier
    }

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
            .font(.ticket(size == .regular ? .amountInput : .amountInputCompact))
            .tracking(size == .regular ? Theme.Tracking.amount : Theme.Tracking.none)
            .foregroundStyle(Theme.ink)
            .keyboardType(.decimalPad)
            .groupsThousands($text)
            .accessibilityIdentifier(identifier ?? "")
    }
}

/// A one-line text field in the ticket's type: comercio, nombre, nota.
struct TicketTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String
    var identifier: String?

    init(_ title: String, text: Binding<String>, prompt: String, identifier: String? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.identifier = identifier
    }

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
            .font(.ticket(.field))
            .tracking(Theme.Tracking.detail)
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier(identifier ?? "")
    }
}

extension View {
    /// Puts the thousands in while an amount is typed ("8000" → "8,000").
    func groupsThousands(_ text: Binding<String>) -> some View {
        modifier(GroupsThousands(text: text))
    }
}

private struct GroupsThousands: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        content.onChange(of: text) { old, new in
            var typed = new
            // Where the decimal pad has a "," key, the comma just typed is the decimal point;
            // the commas already there are the thousands this put in.
            if Locale.current.decimalSeparator == ",", typed.hasSuffix(","), typed.count == old.count + 1 {
                typed = String(typed.dropLast()) + "."
            }
            let shown = AmountTyping.grouped(typed)
            if shown != new { text = shown }
        }
    }
}

#Preview("Campos") {
    @Previewable @State var amount = "1,234.50"
    @Previewable @State var name = ""
    Form {
        Section {
            AmountInputField("Monto", text: $amount, prompt: "0.00")
            TicketTextField("Comercio", text: $name, prompt: "Oxxo, Uber…")
        }
        .listRowBackground(Theme.surface)
        Section {
            AmountInputField("Presupuesto", text: $name, prompt: "8000", size: .compact)
        }
        .listRowBackground(Theme.surface)
    }
    .ticketForm()
    .ticketPreview()
}
