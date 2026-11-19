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
    /// A paste with no amount in it («Pedido 4521 total»): the field went back to what it held
    /// (passed here), and the screen says why (2026-11-18).
    var onUnreadablePaste: ((String) -> Void)?

    /// A literal title (what VoiceOver calls the field): looked up in the catalog. The prompt
    /// is a figure («0.00») and is shown as it is.
    init(_ title: LocalizedStringResource, text: Binding<String>, prompt: String = "0", size: Size = .regular,
         identifier: String? = nil, onPaste: ((ParsedAmount) -> Void)? = nil,
         onUnreadablePaste: ((String) -> Void)? = nil) {
        self.init(String(localized: title), text: text, prompt: prompt, size: size,
                  identifier: identifier, onPaste: onPaste, onUnreadablePaste: onUnreadablePaste)
    }

    /// A title made at run time, shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: String = "0", size: Size = .regular,
                            identifier: String? = nil, onPaste: ((ParsedAmount) -> Void)? = nil,
                            onUnreadablePaste: ((String) -> Void)? = nil) {
        self.title = String(title)
        self._text = text
        self.prompt = prompt
        self.size = size
        self.identifier = identifier
        self.onPaste = onPaste
        self.onUnreadablePaste = onUnreadablePaste
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
            .groupsThousands($text, onPaste: onPaste, onUnreadablePaste: onUnreadablePaste)
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
    func groupsThousands(_ text: Binding<String>, onPaste: ((ParsedAmount) -> Void)? = nil,
                         onUnreadablePaste: ((String) -> Void)? = nil) -> some View {
        modifier(GroupsThousands(text: text, onPaste: onPaste, onUnreadablePaste: onUnreadablePaste))
    }
}

private struct GroupsThousands: ViewModifier {
    @Binding var text: String
    let onPaste: ((ParsedAmount) -> Void)?
    let onUnreadablePaste: ((String) -> Void)?

    func body(content: Content) -> some View {
        content.onChange(of: text) { old, new in
            let commaIsDecimal = Locale.current.decimalSeparator == ","
            switch AmountFieldEdit.read(old: old, new: new, commaIsDecimal: commaIsDecimal) {
            case .typed(let shown):
                if shown != new { text = shown }
            case .pasted(let shown, carried: let carried):
                // A currency or a minus the field cannot keep goes to the screen, not away
                // (2026-11-18).
                if let carried { onPaste?(carried) }
                if shown != new { text = shown }
            case .unreadable:
                // «Pedido 4521 total $230» became 4,521,230 with nothing said (2026-11-18): the
                // field goes back to what it held, and the screen says why.
                text = old
                onUnreadablePaste?(old)
            }
        }
    }
}

/// What a change in the amount field was, and what the field shows after it (2026-11-18).
///
/// A paste is told apart by what it is, not by how much the text grew: «12,50» pasted over
/// «89.00» kept the same length, was read the field's way (commas are thousands) and saved
/// 1,250. Typing on the decimal pad puts in or takes out one run of characters; the field's
/// own rewrite («1,2345» → «12,345») is already written its way. Anything else, or anything
/// with what the pad cannot type («-», «$», letters), is read whole like any amount.
enum AmountFieldEdit: Equatable {
    /// Typed (or the field's own rewrite): what the field shows, thousands put in.
    case typed(String)
    /// Pasted and read whole: what the field shows, and the reading when it carried a
    /// currency or a sign the field cannot keep.
    case pasted(String, carried: ParsedAmount?)
    /// Pasted, and no amount in it: the field keeps what it held.
    case unreadable

    static func read(old: String, new: String, commaIsDecimal: Bool) -> AmountFieldEdit {
        guard isPaste(old: old, new: new) else {
            var typed = new
            // Where the decimal pad has a "," key, the comma just typed is the decimal point;
            // the commas already there are the thousands this put in.
            if commaIsDecimal, typed.hasSuffix(","), typed.count == old.count + 1 {
                typed = String(typed.dropLast()) + "."
            }
            return .typed(AmountTyping.grouped(typed))
        }
        // Read like any amount, so «12,50» is twelve fifty and «1.234,56» is a thousand, then
        // written the way the field writes.
        guard let parsed = AmountParser.parse(new) else { return .unreadable }
        var typed = new
        let pasted = parsed.value.magnitude
        let asWritten = Decimal(string: new.replacingOccurrences(of: ",", with: ""), locale: AmountTyping.written)
        if asWritten != pasted {
            typed = BackupNumber.text(pasted)
            if let dot = typed.firstIndex(of: "."), typed[typed.index(after: dot)...].count == 1 { typed += "0" }
        }
        let carries = new.contains { !isWritten($0) }
        return .pasted(AmountTyping.grouped(typed), carried: carries ? parsed : nil)
    }

    /// Whether `new` came in whole rather than typed.
    static func isPaste(old: String, new: String) -> Bool {
        guard !new.isEmpty else { return false }
        if new.contains(where: { !isWritten($0) }) { return true }
        let before = Array(old)
        let after = Array(new)
        // One key typed, or one run taken out (delete, cut).
        if after.count == before.count + 1, removesOneRun(from: after, leaving: before) { return false }
        if after.count < before.count, removesOneRun(from: before, leaving: after) { return false }
        // Already written the field's way: its own rewrite, or a paste that reads the same.
        return AmountTyping.grouped(new) != new
    }

    /// What the field writes itself: digits, its thousands commas and the decimal point.
    private static func isWritten(_ character: Character) -> Bool {
        (character.isNumber && character.isASCII) || character == "," || character == "."
    }

    /// Whether `shorter` is `longer` with one run of characters taken out.
    private static func removesOneRun(from longer: [Character], leaving shorter: [Character]) -> Bool {
        var start = 0
        while start < shorter.count, longer[start] == shorter[start] { start += 1 }
        let tail = shorter.count - start
        return longer.suffix(tail).elementsEqual(shorter.suffix(tail))
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
