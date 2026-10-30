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
    /// A card or cash: whether it starts as the one already chosen when writing by hand.
    var isDefault = false
    /// With it, the sheet offers «Usar por defecto»; called after `onSave` with the saved name.
    var onSetDefault: ((String, Bool) -> Void)?
    /// Whose colors it picks from, and the others of its kind, so a new one gets a color
    /// none of them has.
    var colorKind: CatalogColors.Kind = .category
    var siblings: [String] = []
    let onSave: (LabeledIcon) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = ""
    @State private var usesByDefault = false
    @State private var color = 0
    @State private var confirmingDelete = false
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
                            .foregroundStyle(Theme.categories[color])
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

                if onSetDefault != nil {
                    Section {
                        Toggle(isOn: $usesByDefault) {
                            SectionLabel("Usar por defecto")
                        }
                        .tint(Theme.brass)
                        .frame(minHeight: Theme.Size.tapTarget)
                        .accessibilityIdentifier("usar-por-defecto")
                    } footer: {
                        HintText("Ya viene elegida cuando anotas un gasto a mano.")
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    ColorRow(selection: $color)
                        .padding(.vertical, Theme.Space.xxs)
                } header: {
                    Text("Color").ticketCaption()
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
                                    .foregroundStyle(selected ? Theme.onBrass : Theme.categories[color])
                                    .frame(maxWidth: .infinity, minHeight: Theme.Size.choiceTile)
                                    .choiceTile(selected: selected)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // VoiceOver reads a name, not «cart.fill»; tests find it by symbol.
                            .accessibilityLabel(IconLabel.name(for: symbol))
                            .accessibilityIdentifier(symbol)
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
                        DestructiveRowButton("Borrar", identifier: "borrar-etiqueta") {
                            confirmingDelete = true
                        }
                        .confirmationDialog("¿Borrar «\(initial?.name ?? "")»?", isPresented: $confirmingDelete,
                                            titleVisibility: .visible) {
                            Button("Borrar", role: .destructive) {
                                onDelete()
                                dismiss()
                            }
                            Button("Conservar", role: .cancel) {}
                        } message: {
                            Text("Los gastos que ya la tienen no cambian.")
                        }
                    } footer: {
                        HintText("Los gastos que ya la tienen no cambian.")
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
                // A renamed one leaves its old name's color behind.
                if let old = initial?.name, !UserCatalog.same(old, trimmed) {
                    UserCatalog.setColor(nil, for: old, key: colorKind.key)
                }
                CatalogColors.set(color, for: trimmed, kind: colorKind)
                onSetDefault?(trimmed, usesByDefault)
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
            usesByDefault = isDefault
            let colors = CatalogColors.current
            color = initial.map { colors.index($0.name, kind: colorKind) }
                ?? colors.nextFree(colorKind, among: siblings)
            nameFocused = initial == nil
        }
    }
}

/// What VoiceOver says for each icon that can be picked, in es-MX, instead of the symbol's
/// technical name («cart.fill»).
enum IconLabel {
    static func name(for symbol: String) -> String {
        names[symbol] ?? "Ícono"
    }

    private static let names: [String: String] = [
        "cart": "Carrito", "fork.knife": "Cubiertos", "cup.and.saucer": "Taza", "car": "Coche",
        "bus": "Autobús", "fuelpump": "Gasolina", "bolt": "Rayo", "drop": "Gota", "wifi": "Wifi",
        "iphone": "Teléfono", "play.rectangle": "Video", "music.note": "Música",
        "gamecontroller": "Control de videojuegos", "wineglass": "Copa", "tshirt": "Playera",
        "bag": "Bolsa", "gift": "Regalo", "cross.case": "Botiquín", "pills": "Medicinas",
        "heart": "Corazón", "dumbbell": "Pesa", "house": "Casa", "bed.double": "Cama",
        "pawprint": "Huella", "graduationcap": "Birrete", "book": "Libro", "airplane": "Avión",
        "suitcase": "Maleta", "wrench.and.screwdriver": "Herramientas", "scissors": "Tijeras",
        "sparkles": "Destellos", "figure.2.and.child.holdinghands": "Familia",
        "briefcase": "Portafolio", "building.2": "Edificio", "leaf": "Hoja", "tag": "Etiqueta",
        "creditcard": "Tarjeta", "creditcard.fill": "Tarjeta rellena", "wallet.pass": "Wallet",
        "banknote": "Billete", "dollarsign.circle": "Signo de dinero", "building.columns": "Banco",
        "applelogo": "Apple", "giftcard": "Tarjeta de regalo", "person.2": "Personas", "star": "Estrella",
    ]
}
