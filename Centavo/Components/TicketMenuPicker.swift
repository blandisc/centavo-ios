import SwiftUI

/// A choice that opens the system's menu, with its value in the ticket's typeface and in brass
/// (it is touched): «TIPO · No cuenta ⌃⌄». The whole row opens the menu, not only the value at
/// its far end. The system's own `Picker` with `.pickerStyle(.menu)` writes its value in the
/// iPhone's typeface, the only text of the app outside the ticket's (owner, 2026-11-11): every
/// menu choice inside a form uses this instead, and `Tools/lint-design.sh` fails otherwise.
/// Dates (`DatePicker`) and segmented choices stay the system's.
struct TicketMenuPicker<Value: Hashable, Label: View, Options: View>: View {
    /// What VoiceOver and the menu call the choice.
    let title: String
    @Binding var selection: Value
    /// The chosen option, as written in the row.
    let value: String
    @ViewBuilder var options: () -> Options
    @ViewBuilder var label: () -> Label

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, selection: Binding<Value>, value: String,
         @ViewBuilder options: @escaping () -> Options, @ViewBuilder label: @escaping () -> Label) {
        self.title = title
        _selection = selection
        self.value = value
        self.options = options
        self.label = label
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection, content: options)
        } label: {
            row
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
        }
    }

    /// With an accessibility text size the value goes under its label instead of being cut.
    @ViewBuilder private var row: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                label()
                chosen
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: Theme.Space.s) {
                label()
                Spacer(minLength: Theme.Space.s)
                chosen
            }
        }
    }

    private var chosen: some View {
        HStack(spacing: Theme.Space.s) {
            Text(value)
                .font(.ticket(.body))
                .foregroundStyle(Theme.brass)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            Image(systemName: "chevron.up.chevron.down")
                .font(Theme.Symbol.regular)
                .imageScale(.small)
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
        }
    }
}

extension TicketMenuPicker where Label == SectionLabel {
    /// The usual row of a form: the title as a `SectionLabel` («TIPO», «MOTIVO»).
    init(_ title: String, selection: Binding<Value>, value: String,
         @ViewBuilder options: @escaping () -> Options) {
        self.init(title, selection: selection, value: value, options: options) { SectionLabel(title) }
    }
}

#Preview("Selector de menú") {
    @Previewable @State var kind = "No cuenta"
    @Previewable @State var currency = "MXN"
    Form {
        Section {
            TicketMenuPicker("Tipo", selection: $kind, value: kind) {
                ForEach(["Gasto", "Devolución", "No cuenta"], id: \.self) { Text($0).tag($0) }
            }
            TicketMenuPicker("Moneda principal", selection: $currency, value: "Pesos (\(currency))") {
                ForEach(["MXN", "USD"], id: \.self) { Text($0).tag($0) }
            } label: {
                IconRow("Moneda principal", systemImage: "dollarsign.circle")
            }
        } header: {
            Text("Selectores").ticketCaption()
        }
        .listRowBackground(Theme.surface)
    }
    .ticketForm()
    .ticketPreview()
}
