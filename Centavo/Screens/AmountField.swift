import CentavoCore
import SwiftUI

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
