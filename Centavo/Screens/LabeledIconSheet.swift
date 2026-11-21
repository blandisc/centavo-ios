import SwiftUI

/// Names something and gives it an icon: a new category, or a card or cash to pay with.
struct LabeledIconSheet: View {
    let title: LocalizedStringResource
    let prompt: LocalizedStringResource
    let icons: [String]
    /// Names already taken, which cannot be used twice.
    let taken: [String]
    var initial: LabeledIcon?
    /// Shown as «Borrar» when editing one that exists.
    var onDelete: (() -> Void)?
    /// What «Borrar» asks first, when the caller knows more than the name (how many expenses
    /// have it); without it, the name and that the expenses don't change.
    var deleteQuestion: TicketQuestion?
    /// A card or cash: whether it starts as the one already chosen when writing by hand.
    var isDefault = false
    /// With it, the sheet offers «Usar por defecto»; called after `onSave` with the saved name.
    var onSetDefault: ((String, Bool) -> Void)?
    /// Whose colors it picks from, and the others of its kind, so a new one gets a color
    /// none of them has.
    var colorKind: CatalogColors.Kind = .category
    var siblings: [String] = []
    /// Saving that can fail (a rename that must reach the expenses), used instead of `onSave`:
    /// `false` keeps the sheet open with what was typed, says so, and moves no color, so it can
    /// be tried again.
    var commit: ((LabeledIcon) -> Bool)?
    let onSave: (LabeledIcon) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = ""
    @State private var usesByDefault = false
    @State private var color = 0
    @State private var confirmingDelete = false
    /// «Cancelar» or a swipe down with something changed: «¿Descartar cambios?».
    @State private var askingDiscard = false
    @State private var saveFailed = false
    /// How it opened (`snapshot`), to tell whether anything changed.
    @State private var loaded: [String]?
    @FocusState private var nameFocused: Bool
    @ScaledMetric(relativeTo: .body) private var iconColumn = Theme.Size.iconColumnWide

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    /// The name as it is kept: one of the app's own typed in the iPhone's language («Groceries»,
    /// «Cash») is kept in Spanish, so it is never a second one (2026-11-18).
    /// A name left as it was shown keeps the name it had: in English a source of its own called
    /// «Cash» (or a category «Casa») went through the translation and came back as another
    /// («Efectivo», «Hogar»), renaming its expenses into it (independent review, 2026-11-18).
    private var stored: String {
        if let initial, UserCatalog.same(trimmed, CategoryStyle.shown(initial.name)) { return initial.name }
        return colorKind == .source ? CategoryStyle.storedPayment(trimmed) : CategoryStyle.stored(trimmed)
    }
    /// What the save bar says: what is missing, or the name that will be saved.
    private var saveSummary: String {
        if trimmed.isEmpty { return String(localized: "Falta el nombre") }
        if isTaken { return String(localized: "Ya tienes una con ese nombre") }
        return trimmed
    }
    private var isTaken: Bool {
        let wanted = stored
        return taken.contains { UserCatalog.same($0, wanted) && !UserCatalog.same($0, initial?.name ?? "") }
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
                            .ticketField()
                            .textInputAutocapitalization(.words)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityIdentifier("nombre-nuevo")
                    }
                } header: {
                    Text("Nombre").ticketCaption()
                } footer: {
                    if isTaken {
                        NoteText("Ya tienes una con ese nombre.", color: Theme.danger)
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

                if initial != nil, onDelete != nil {
                    Section {
                        DestructiveRowButton("Borrar", identifier: "borrar-etiqueta") {
                            confirmingDelete = true
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
            .saveBar(saveSummary,
                     enabled: !trimmed.isEmpty && !isTaken, identifier: "guardar-nuevo", action: save)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if hasChanges { askingDiscard = true } else { dismiss() }
                    }
                    .font(.ticket(.footnote))
                }
            }
            .problemAlert("No se cambió el nombre", isPresented: $saveFailed, retry: save)
            .confirmsRemoval(isPresented: $confirmingDelete, question: {
                deleteQuestion ?? plainDeleteQuestion
            }) {
                onDelete?()
                dismiss()
            }
        }
        .presentationDetents([.large])
        .onAppear {
            name = initial.map { CategoryStyle.shown($0.name) } ?? ""
            icon = initial?.icon ?? (icons.first ?? "tag")
            usesByDefault = isDefault
            let colors = CatalogColors.current
            color = initial.map { colors.index($0.name, kind: colorKind) }
                ?? colors.nextFree(colorKind, among: siblings)
            nameFocused = initial == nil
            loaded = snapshot
        }
        // «Cancelar» or a swipe down ask before throwing away a name, an icon or a color just picked.
        .confirmsDiscard(hasChanges: hasChanges, isAsking: $askingDiscard) { dismiss() }
    }

    /// What «Borrar» asks when the caller gave no question of its own.
    private var plainDeleteQuestion: TicketQuestion {
        let title: String
        if colorKind == .source {
            title = String(localized: "¿Borrar esta forma de pago?")
        } else {
            title = String(localized: "¿Borrar esta categoría?")
        }
        return TicketQuestion(title: title, name: initial.map { CategoryStyle.shown($0.name) } ?? "",
                              note: String(localized: "Los gastos que ya la tienen no cambian."))
    }

    /// Saves it and closes; a rename that fails stays open, with «Intentar otra vez».
    private func save() {
        let saved = stored
        let item = LabeledIcon(name: saved, icon: icon.isEmpty ? (icons.first ?? "tag") : icon)
        if let commit {
            guard commit(item) else {
                saveFailed = true
                return
            }
        } else {
            onSave(item)
        }
        // A renamed one leaves its old name's color behind.
        if let old = initial?.name, !UserCatalog.same(old, saved) {
            UserCatalog.setColor(nil, for: old, key: colorKind.key)
        }
        CatalogColors.set(color, for: saved, kind: colorKind)
        onSetDefault?(saved, usesByDefault)
        dismiss()
    }

    /// What can be changed here, as it is now.
    private var snapshot: [String] { [name, icon, "\(usesByDefault)", "\(color)"] }
    private var hasChanges: Bool { loaded.map { $0 != snapshot } ?? false }
}

/// What VoiceOver says for each icon that can be picked, in the iPhone's language, instead of
/// the symbol's technical name («cart.fill»). One `return` per symbol: a dictionary literal of
/// localized strings is slow for the CI's type-checker.
enum IconLabel {
    static func name(for symbol: String) -> String {
        switch symbol {
        case "cart": return String(localized: "Carrito")
        case "fork.knife": return String(localized: "Cubiertos")
        case "cup.and.saucer": return String(localized: "Taza")
        case "car": return String(localized: "Coche")
        case "bus": return String(localized: "Autobús")
        case "fuelpump": return String(localized: "Gasolina")
        case "bolt": return String(localized: "Rayo")
        case "drop": return String(localized: "Gota")
        case "wifi": return String(localized: "Wifi")
        case "iphone": return String(localized: "Teléfono")
        case "play.rectangle": return String(localized: "Video")
        case "music.note": return String(localized: "Música")
        case "gamecontroller": return String(localized: "Control de videojuegos")
        case "wineglass": return String(localized: "Copa")
        case "tshirt": return String(localized: "Playera")
        case "bag": return String(localized: "Bolsa")
        case "gift": return String(localized: "Regalo")
        case "cross.case": return String(localized: "Botiquín")
        case "pills": return String(localized: "Medicinas")
        case "heart": return String(localized: "Corazón")
        case "dumbbell": return String(localized: "Pesa")
        case "house": return String(localized: "Casa")
        case "bed.double": return String(localized: "Cama")
        case "pawprint": return String(localized: "Huella")
        case "graduationcap": return String(localized: "Birrete")
        case "book": return String(localized: "Libro")
        case "airplane": return String(localized: "Avión")
        case "suitcase": return String(localized: "Maleta")
        case "wrench.and.screwdriver": return String(localized: "Herramientas")
        case "scissors": return String(localized: "Tijeras")
        case "sparkles": return String(localized: "Destellos")
        case "figure.2.and.child.holdinghands": return String(localized: "Familia")
        case "briefcase": return String(localized: "Portafolio")
        case "building.2": return String(localized: "Edificio")
        case "leaf": return String(localized: "Hoja")
        case "tag": return String(localized: "Etiqueta")
        case "creditcard": return String(localized: "Tarjeta")
        case "creditcard.fill": return String(localized: "Tarjeta rellena")
        case "wallet.pass": return "Wallet"
        case "banknote": return String(localized: "Billete")
        case "dollarsign.circle": return String(localized: "Signo de dinero")
        case "building.columns": return String(localized: "Banco")
        case "applelogo": return "Apple"
        case "giftcard": return String(localized: "Tarjeta de regalo")
        case "person.2": return String(localized: "Personas")
        case "star": return String(localized: "Estrella")
        default: return String(localized: "Ícono")
        }
    }
}
