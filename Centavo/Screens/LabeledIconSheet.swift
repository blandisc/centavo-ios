import SwiftUI

/// Names something and gives it an icon: a new category, or a card or cash to pay with.
struct LabeledIconSheet: View {
    let title: String
    let prompt: String
    let icons: [String]
    /// Names already taken, which cannot be used twice.
    let taken: [String]
    var initial: LabeledIcon?
    /// Shown as «Borrar» when editing one that exists.
    var onDelete: (() -> Void)?
    let onSave: (LabeledIcon) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = ""
    @FocusState private var nameFocused: Bool
    @ScaledMetric(relativeTo: .body) private var iconColumn = Theme.Size.iconColumnWide

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isTaken: Bool {
        taken.contains { UserCatalog.same($0, trimmed) && !UserCatalog.same($0, initial?.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: icon.isEmpty ? (icons.first ?? "tag") : icon)
                            .font(Theme.Symbol.large)
                            .foregroundStyle(Theme.brass)
                            .frame(width: iconColumn)
                            .accessibilityHidden(true)
                        TextField("Nombre", text: $name, prompt: Text(prompt).foregroundStyle(Theme.faint))
                            .font(.ticket(.field))
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
                        NoteText("Ya tienes uno con ese nombre.", color: Theme.danger)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.choiceTile), spacing: Theme.Space.s)],
                              spacing: Theme.Space.s) {
                        ForEach(icons, id: \.self) { symbol in
                            let selected = symbol == icon
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(Theme.Symbol.large)
                                    .foregroundStyle(selected ? Theme.onBrass : Theme.brass)
                                    .frame(maxWidth: .infinity, minHeight: Theme.Size.choiceTile)
                                    .choiceTile(selected: selected)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                } header: {
                    Text("Ícono").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                if initial != nil, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Borrar")
                                .font(.ticket(.footnoteStrong))
                                .tracking(Theme.Tracking.caption)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                        }
                        .accessibilityIdentifier("borrar-etiqueta")
                    } footer: {
                        NoteText("Los gastos que ya la tienen no cambian.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            // Like the other sheets: moving the form puts the keyboard away, so every icon shows.
            .scrollDismissesKeyboard(.immediately)
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
                        .font(.ticket(.footnote))
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
