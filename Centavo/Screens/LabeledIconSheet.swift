import SwiftUI

/// Names something and gives it an icon: a new category, or a card or cash to pay with.
struct LabeledIconSheet: View {
    let title: String
    let prompt: String
    let icons: [String]
    /// Names already taken, which cannot be used twice.
    let taken: [String]
    var initial: LabeledIcon?
    let onSave: (LabeledIcon) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = ""
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isTaken: Bool {
        taken.contains { UserCatalog.same($0, trimmed) && !UserCatalog.same($0, initial?.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: icon.isEmpty ? (icons.first ?? "tag") : icon)
                            .font(.title3)
                            .foregroundStyle(Theme.brass)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        TextField("Nombre", text: $name, prompt: Text(prompt).foregroundStyle(Theme.faint))
                            .font(.ticket(17, relativeTo: .body))
                            .foregroundStyle(Theme.ink)
                            .textInputAutocapitalization(.words)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityIdentifier("nombre-nuevo")
                    }
                } header: {
                    Text("Nombre").ticketCaption()
                } footer: {
                    if isTaken {
                        Text("Ya tienes uno con ese nombre.")
                            .font(.ticket(12, relativeTo: .footnote))
                            .foregroundStyle(Theme.danger)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                        ForEach(icons, id: \.self) { symbol in
                            let selected = symbol == icon
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .foregroundStyle(selected ? Theme.onBrass : Theme.brass)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(selected ? Theme.brass : Theme.background,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Ícono").ticketCaption()
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(title)
            .saveBar(trimmed.isEmpty ? "Falta el nombre" : isTaken ? "Ya tienes uno con ese nombre" : trimmed,
                     enabled: !trimmed.isEmpty && !isTaken, identifier: "guardar-nuevo") {
                onSave(LabeledIcon(name: trimmed, icon: icon.isEmpty ? (icons.first ?? "tag") : icon))
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(13, relativeTo: .footnote))
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            name = initial?.name ?? ""
            icon = initial?.icon ?? (icons.first ?? "tag")
            nameFocused = initial == nil
        }
    }
}
