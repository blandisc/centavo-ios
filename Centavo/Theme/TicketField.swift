import SwiftUI

/// One line of the ticket form: a small caption over a text field, closed by a perforation.
struct TicketField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var capitalization: TextInputAutocapitalization = .words
    var identifier = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).ticketCaption()
            TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
                .font(.ticket(17, relativeTo: .body))
                .tracking(0.6)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(capitalization)
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Perforation() }
    }
}
