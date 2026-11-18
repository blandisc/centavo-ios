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
    /// What was pasted, read whole, when it carried what the decimal pad cannot type: a
    /// currency («USD 25.00», «€20») or a minus («-$50», «(50.00)»). The field keeps only the
    /// figure; the screen decides what to do with the rest (2026-11-18).
    var onPaste: ((ParsedAmount) -> Void)?

    /// A literal title (what VoiceOver calls the field): looked up in the catalog. The prompt
    /// is a figure («0.00») and is shown as it is.
    init(_ title: LocalizedStringResource, text: Binding<String>, prompt: String = "0", size: Size = .regular,
         identifier: String? = nil, onPaste: ((ParsedAmount) -> Void)? = nil) {
        self.init(String(localized: title), text: text, prompt: prompt, size: size,
                  identifier: identifier, onPaste: onPaste)
    }

    /// A title made at run time, shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: String = "0", size: Size = .regular,
                            identifier: String? = nil, onPaste: ((ParsedAmount) -> Void)? = nil) {
        self.title = String(title)
        self._text = text
        self.prompt = prompt
        self.size = size
        self.identifier = identifier
        self.onPaste = onPaste
    }

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
            .font(.ticket(size == .regular ? .amountInput : .amountInputCompact))
            .tracking(size == .regular ? Theme.Tracking.amount : Theme.Tracking.none)
            // A big figure beside «MXN ⌄» shrinks rather than hide its cents (2026-11-18).
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.figure)
            .foregroundStyle(Theme.ink)
            .keyboardType(.decimalPad)
            .groupsThousands($text, onPaste: onPaste)
            .anchorsRowSeparator()
            .accessibilityIdentifier(identifier ?? "")
    }
}

/// A one-line text field in the ticket's type: comercio, nombre, nota.
struct TicketTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String
    var identifier: String?

    /// A literal title (what VoiceOver calls the field): looked up in the catalog. The prompt
    /// is shown as it is: pass `String(localized: "…")` when it is words, not a name.
    init(_ title: LocalizedStringResource, text: Binding<String>, prompt: String, identifier: String? = nil) {
        self.init(String(localized: title), text: text, prompt: prompt, identifier: identifier)
    }

    /// A title made at run time, shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: String, identifier: String? = nil) {
        self.title = String(title)
        self._text = text
        self.prompt = prompt
        self.identifier = identifier
    }

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
            .ticketField()
            .accessibilityIdentifier(identifier ?? "")
    }
}

extension View {
    /// What makes a text field the ticket's (owner, 2026-11-16, D8-A): its letter and spacing,
    /// ink for what's typed, and the row's line starting at its edge. Every `TextField` wears it
    /// (`Tools/lint-design.py`, `ticket-field`); the prompt stays `Theme.faint`.
    func ticketField(_ style: TicketStyle = .field) -> some View {
        font(.ticket(style))
            .tracking(Theme.Tracking.detail)
            .foregroundStyle(Theme.ink)
            .anchorsRowSeparator()
    }

    /// The line under a form row starts at this field's edge. Left alone, iOS starts it at the
    /// row's first text: beside a field that is the currency menu, and under «Monto» the line
    /// showed only beneath «MXN», as if broken (owner, 2026-11-14). Every field component carries
    /// it (`Tools/lint-design.py`, `field-separator`).
    func anchorsRowSeparator() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    /// Puts the thousands in while an amount is typed ("8000" → "8,000").
    func groupsThousands(_ text: Binding<String>, onPaste: ((ParsedAmount) -> Void)? = nil) -> some View {
        modifier(GroupsThousands(text: text, onPaste: onPaste))
    }
}

private struct GroupsThousands: ViewModifier {
    @Binding var text: String
    let onPaste: ((ParsedAmount) -> Void)?

    func body(content: Content) -> some View {
        content.onChange(of: text) { old, new in
            var typed = new
            // Pasted (more than one character at once): read like any amount, so «12,50» is
            // twelve fifty and «1.234,56» is a thousand, then written the way the field writes.
            // Only when the field's own reading (commas are thousands) would get it wrong.
            if new.count > old.count + 1, let parsed = AmountParser.parse(new) {
                // A currency or a minus the field cannot keep goes to the screen, not away
                // (2026-11-18). Only what the field never writes itself, so its own rewrite
                // («1234567» → «1,234,567») is not taken for a paste.
                if new.contains(where: { !($0.isNumber || $0 == "," || $0 == ".") }) { onPaste?(parsed) }
                let pasted = parsed.value.magnitude
                if Decimal(string: new.replacingOccurrences(of: ",", with: ""),
                           locale: Locale(identifier: "en_US_POSIX")) != pasted {
                    typed = BackupNumber.text(pasted)
                    if let dot = typed.firstIndex(of: "."), typed[typed.index(after: dot)...].count == 1 { typed += "0" }
                }
            }
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
