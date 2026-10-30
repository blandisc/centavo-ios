import CentavoCore
import SwiftData
import SwiftUI

/// «Pagos y categorías»: the ways someone pays (one of them the default for what they
/// write down by hand) and the categories of their own, each with its icon.
struct CatalogSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserCatalog.sourcesKey) private var storedSources = ""
    @AppStorage(UserCatalog.defaultSourceKey) private var defaultSource = ""
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var storedHidden = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    @AppStorage(UserCatalog.sourceColorsKey) private var storedSourceColors = ""
    @Query private var expenses: [Expense]
    @State private var editing: Editing?
    /// A card or category about to be deleted, waiting for «Borrar».
    @State private var confirmingRemoval: Editing?

    private enum Editing: Identifiable {
        case source(LabeledIcon?), category(LabeledIcon?)
        var id: String {
            switch self {
            case .source(let item): "s-" + (item?.name ?? "")
            case .category(let item): "c-" + (item?.name ?? "")
            }
        }
    }

    private var sources: [LabeledIcon] { UserCatalog.decode(storedSources) }
    private var categories: [LabeledIcon] { UserCatalog.decode(storedCategories) }
    private var hidden: [String] { UserCatalog.decodeNames(storedHidden) }

    /// The app's own categories and any other already used, less the ones made here (those
    /// are deleted instead): what can be hidden from the picker.
    private var others: [String] {
        let used = CategoryMemory.known(in: expenses.map(\.categorized))
        var names: [String] = []
        for name in CategoryStyle.common.map(\.name) + used
        where !names.contains(where: { UserCatalog.same($0, name) })
            && !categories.contains(where: { UserCatalog.same($0.name, name) }) {
            names.append(name)
        }
        return names
    }

    private var colors: CatalogColors {
        CatalogColors(categories: storedCategoryColors, sources: storedSourceColors)
    }

    /// The color of a card or category, for its «Color» menu.
    private func color(_ name: String, _ kind: CatalogColors.Kind) -> Binding<Int> {
        Binding(get: { colors.index(name, kind: kind) },
                set: { CatalogColors.set($0, for: name, kind: kind) })
    }

    private func shows(_ name: String) -> Binding<Bool> {
        Binding(get: { !hidden.contains { UserCatalog.same($0, name) } }, set: { show in
            var list = hidden.filter { !UserCatalog.same($0, name) }
            if !show { list.append(name) }
            storedHidden = UserCatalog.encodeNames(list)
        })
    }

    /// Cards that came with payments (Wallet names them) but were never set up here: they
    /// show beside the saved ones, so the screen is never empty for someone using Wallet.
    private var detectedCards: [String] {
        var names: [String] = []
        for expense in expenses {
            guard let card = expense.card?.trimmingCharacters(in: .whitespaces), !card.isEmpty,
                  !sources.contains(where: { UserCatalog.same($0.name, card) }),
                  !names.contains(where: { UserCatalog.same($0, card) }) else { continue }
            names.append(card)
        }
        return names
    }

    /// Every category in one place: yours first, then the usual ones and any other used.
    private var allCategories: [(name: String, icon: String, isCustom: Bool)] {
        categories.map { ($0.name, $0.icon, true) }
            + others.map { ($0, CategoryStyle.icon(for: $0, custom: categories), false) }
    }

    /// A card that came with payments gets a banknote if it is cash, a card otherwise.
    static func guessIcon(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.contains("efectivo") || folded.contains("cash") ? "banknote" : "creditcard"
    }

    private let columns = [GridItem(.adaptive(minimum: Theme.Size.catalogTile), spacing: Theme.Space.s)]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                        ForEach(sources) { source in
                            let isDefault = UserCatalog.same(source.name, defaultSource)
                            Menu {
                                if !isDefault {
                                    Button("Usar por defecto", systemImage: "star") { defaultSource = source.name }
                                }
                                Button("Editar", systemImage: "pencil") { editing = .source(source) }
                                ColorMenu(selection: color(source.name, .source))
                                Button("Borrar", systemImage: "trash", role: .destructive) {
                                    confirmingRemoval = .source(source)
                                }
                            } label: {
                                CategoryTile(name: source.name, icon: source.icon, color: colors.source(source.name),
                                            badge: isDefault ? "star.fill" : nil, twoLines: true)
                            }
                            .accessibilityLabel(isDefault ? "\(source.name), predeterminada" : source.name)
                            .accessibilityIdentifier("fuente-\(source.name)")
                        }
                        ForEach(detectedCards, id: \.self) { card in
                            Menu {
                                Button("Usar por defecto", systemImage: "star") {
                                    save(LabeledIcon(name: card, icon: Self.guessIcon(card)), replacing: nil)
                                    defaultSource = card
                                }
                                Button("Elegir ícono", systemImage: "square.grid.2x2") {
                                    editing = .source(LabeledIcon(name: card, icon: Self.guessIcon(card)))
                                }
                                ColorMenu(selection: color(card, .source))
                            } label: {
                                CategoryTile(name: card, icon: Self.guessIcon(card), color: colors.source(card),
                                            badge: "wave.3.right", twoLines: true)
                            }
                            .accessibilityLabel("\(card), llegó en tus pagos")
                            .accessibilityIdentifier("fuente-\(card)")
                        }
                        Button { editing = .source(nil) } label: {
                            CategoryTile(name: "Nueva", icon: "plus", isAction: true, twoLines: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nueva forma de pago")
                        .accessibilityIdentifier("agregar-fuente")
                    }
                    .padding(.vertical, Theme.Space.xs)
                } header: {
                    Text("Formas de pago").ticketCaption()
                } footer: {
                    HintText(Text("\(Image(systemName: "star.fill")) ya viene elegida cuando anotas a mano. \(Image(systemName: "wave.3.right")) llegó en tus pagos de Wallet: tócala para usarla por defecto o darle ícono."))
                }
                .listRowBackground(Theme.surface)

                Section {
                    LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                        ForEach(allCategories, id: \.name) { item in
                            let shown = shows(item.name)
                            Menu {
                                Button(shown.wrappedValue ? "Ocultar al anotar" : "Mostrar al anotar",
                                       systemImage: shown.wrappedValue ? "eye.slash" : "eye") {
                                    withAnimation(Theme.Motion.quick) { shown.wrappedValue.toggle() }
                                }
                                ColorMenu(selection: color(item.name, .category))
                                if item.isCustom, let custom = categories.first(where: { $0.name == item.name }) {
                                    Button("Editar", systemImage: "pencil") { editing = .category(custom) }
                                    Button("Borrar", systemImage: "trash", role: .destructive) {
                                        confirmingRemoval = .category(custom)
                                    }
                                }
                            } label: {
                                CategoryTile(name: item.name, icon: item.icon, color: colors.category(item.name),
                                            badge: shown.wrappedValue ? nil : "eye.slash",
                                            dimmed: !shown.wrappedValue, twoLines: true)
                            }
                            .accessibilityLabel(shown.wrappedValue ? item.name : "\(item.name), oculta")
                            .accessibilityIdentifier("mostrar-\(item.name)")
                        }
                        Button { editing = .category(nil) } label: {
                            CategoryTile(name: "Nueva", icon: "plus", isAction: true, twoLines: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nueva categoría")
                        .accessibilityIdentifier("agregar-categoria")
                    }
                    .padding(.vertical, Theme.Space.xs)
                } header: {
                    Text("Categorías").ticketCaption()
                } footer: {
                    HintText("Toca una para ocultarla al anotar, o para cambiar las tuyas. Los gastos que ya la tienen no cambian.")
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Pagos y categorías")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(.footnoteStrong))
                }
            }
            .sheet(item: $editing) { item in
                switch item {
                case .source(let source):
                    LabeledIconSheet(title: source == nil ? "Nueva forma de pago" : "Editar forma de pago",
                                     prompt: "BBVA, Nu, Efectivo…", icons: UserCatalog.sourceIcons,
                                     taken: sources.map(\.name), initial: source,
                                     onDelete: source.map { item in { remove(item) } },
                                     isDefault: source.map { UserCatalog.same($0.name, defaultSource) }
                                        ?? sources.isEmpty,
                                     onSetDefault: setDefault, colorKind: .source,
                                     siblings: sources.map(\.name) + detectedCards) { saved in
                        save(saved, replacing: source)
                    }
                case .category(let category):
                    LabeledIconSheet(title: category == nil ? "Nueva categoría" : "Editar categoría",
                                     prompt: "Mascotas, Gimnasio…", icons: UserCatalog.categoryIcons,
                                     taken: categories.map(\.name) + CategoryStyle.common.map(\.name),
                                     initial: category,
                                     onDelete: category.map { item in { removeCategory(item) } },
                                     colorKind: .category, siblings: allCategories.map(\.name)) { saved in
                        var list = categories
                        if let category, let index = list.firstIndex(of: category) {
                            list[index] = saved
                            UserCatalog.renameCategory(category.name, to: saved.name)
                        } else { list.append(saved) }
                        storedCategories = UserCatalog.encode(list)
                        UserCatalog.markDeleted(saved.name, false)
                    }
                }
            }
            .confirmationDialog(confirmationTitle, isPresented: confirmingBinding, titleVisibility: .visible,
                                presenting: confirmingRemoval) { item in
                Button("Borrar", role: .destructive) {
                    switch item {
                    case .source(let source?): remove(source)
                    case .category(let category?): removeCategory(category)
                    default: break
                    }
                }
                Button("Conservar", role: .cancel) {}
            } message: { _ in
                Text("Los gastos que ya la tienen no cambian.")
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmingRemoval {
        case .source(let item?), .category(let item?): "¿Borrar «\(item.name)»?"
        default: ""
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } })
    }

    /// «Usar por defecto» in the card's sheet: on makes it the one already chosen; off on the
    /// current one leaves none chosen.
    private func setDefault(_ name: String, _ on: Bool) {
        if on {
            defaultSource = name
        } else if UserCatalog.same(defaultSource, name) {
            defaultSource = ""
        }
    }

    private func save(_ source: LabeledIcon, replacing old: LabeledIcon?) {
        var list = sources
        if let old, let index = list.firstIndex(of: old) {
            list[index] = source
            if UserCatalog.same(defaultSource, old.name) { defaultSource = source.name }
        } else {
            list.append(source)
            // The first one is the default until another is chosen.
            if defaultSource.isEmpty { defaultSource = source.name }
        }
        storedSources = UserCatalog.encode(list)
    }

    /// Expenses that have a deleted category keep it, and if any does it stays in the picker;
    /// it is just never filled in on its own again.
    private func removeCategory(_ category: LabeledIcon) {
        storedCategories = UserCatalog.encode(categories.filter { $0 != category })
        UserCatalog.markDeleted(category.name, true)
        UserCatalog.setColor(nil, for: category.name, key: UserCatalog.categoryColorsKey)
    }

    private func remove(_ source: LabeledIcon) {
        let list = sources.filter { $0 != source }
        storedSources = UserCatalog.encode(list)
        UserCatalog.setColor(nil, for: source.name, key: UserCatalog.sourceColorsKey)
        if UserCatalog.same(defaultSource, source.name) { defaultSource = list.first?.name ?? "" }
    }
}
