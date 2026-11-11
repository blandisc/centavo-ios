import CentavoCore
import SwiftData
import SwiftUI

/// «Pagos y categorías»: the ways someone pays (one of them the default for what they
/// write down by hand) and the categories of their own, each with its icon.
struct CatalogSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @AppStorage(UserCatalog.sourcesKey) private var storedSources = ""
    @AppStorage(UserCatalog.defaultSourceKey) private var defaultSource = ""
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var storedHidden = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    @AppStorage(UserCatalog.sourceColorsKey) private var storedSourceColors = ""
    /// The categories and cards the expenses use, read with only those two fields when the
    /// screen opens (audit 2026-11-02: a live query loaded every expense whole).
    @State private var used = UsedNames()
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
        var names: [String] = []
        for name in CategoryStyle.common.map(\.name) + used.categories
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
            storedHidden = UserCatalog.encodeNames(list, keepingUnreadFrom: storedHidden)
        })
    }

    /// Cards that came with payments (Wallet names them) but were never set up here: they
    /// show beside the saved ones, so the screen is never empty for someone using Wallet.
    private var detectedCards: [String] {
        var names: [String] = []
        for name in used.cards {
            let card = name.trimmingCharacters(in: .whitespaces)
            guard !card.isEmpty,
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
                            .accessibilityLabel(isDefault ? "\(source.name), por defecto" : source.name)
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
                                    withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                                        shown.wrappedValue.toggle()
                                    }
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
                    HintText("Toca una para ocultarla al anotar, o para cambiar las tuyas. Ocultarla o borrarla no cambia los gastos que ya la tienen; cambiarle el nombre, sí.")
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
                    LabeledIconSheet(title: "Forma de pago",
                                     prompt: "BBVA, Nu, Efectivo…", icons: UserCatalog.sourceIcons,
                                     taken: sources.map(\.name), initial: source,
                                     // One that only arrived in payments isn't in the list: nothing to delete.
                                     onDelete: source.flatMap { item in
                                         sources.contains { UserCatalog.same($0.name, item.name) } ? { remove(item) } : nil
                                     },
                                     isDefault: source.map { UserCatalog.same($0.name, defaultSource) }
                                        ?? sources.isEmpty,
                                     onSetDefault: setDefault, colorKind: .source,
                                     siblings: sources.map(\.name) + detectedCards, commit: { saved in
                        // The expenses first: if they can't be saved, nothing else changes.
                        if let source {
                            guard rename(.card, from: source.name, to: saved.name) else { return false }
                        }
                        save(saved, replacing: source)
                        return true
                    }, onSave: { _ in })
                case .category(let category):
                    LabeledIconSheet(title: category == nil ? "Nueva categoría" : "Editar categoría",
                                     prompt: "Mascotas, Gimnasio…", icons: UserCatalog.categoryIcons,
                                     taken: categories.map(\.name) + CategoryStyle.common.map(\.name),
                                     initial: category,
                                     onDelete: category.map { item in { removeCategory(item) } },
                                     colorKind: .category, siblings: allCategories.map(\.name), commit: { saved in
                        var list = categories
                        if let category, let index = list.firstIndex(of: category) {
                            // The expenses first: if they can't be saved, nothing else changes.
                            guard rename(.category, from: category.name, to: saved.name) else { return false }
                            list[index] = saved
                            UserCatalog.renameCategory(category.name, to: saved.name)
                        } else { list.append(saved) }
                        storedCategories = UserCatalog.encode(list, keepingUnreadFrom: storedCategories)
                        UserCatalog.markDeleted(saved.name, false)
                        return true
                    }, onSave: { _ in })
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
            .onAppear { used = UsedNames.read(in: context) }
            // A payment that lands, or iCloud, while it is open.
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                used = UsedNames.read(in: context)
            }
        }
    }

    private enum Renamed { case category, card }

    /// A category or card renamed here renames it in the expenses that have it too, all in one
    /// save, and in the fixed expenses still to start: otherwise the old name stays on them and
    /// the category is split in two (audit 2026-11-02). Same comparison as everywhere: case,
    /// accents and spaces don't count. A card's new name is also remembered, so Wallet's next
    /// payment with the old one arrives renamed. `false` if the expenses couldn't be saved:
    /// then nothing changed, and it can be tried again.
    private func rename(_ kind: Renamed, from old: String, to new: String) -> Bool {
        guard old != new else { return true }
        let field: ReferenceWritableKeyPath<Expense, String?> = kind == .card ? \.card : \.category
        let all = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let matching = all.filter { $0[keyPath: field].map { UserCatalog.same($0, old) } ?? false }
        if !matching.isEmpty {
            for expense in matching { expense[keyPath: field] = new }
            do {
                try context.save()
            } catch {
                context.rollback()
                return false
            }
        }
        let plans = FixedPlan.saved
        let renamedPlans = plans.map { plan -> FixedPlan in
            var plan = plan
            switch kind {
            case .category: if plan.category.map({ UserCatalog.same($0, old) }) == true { plan.category = new }
            case .card: if plan.card.map({ UserCatalog.same($0, old) }) == true { plan.card = new }
            }
            return plan
        }
        if renamedPlans != plans { FixedPlan.save(renamedPlans) }
        if kind == .card { UserCatalog.learnCardRename(old, to: new) }
        used = UsedNames.read(in: context)
        return true
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
        storedSources = UserCatalog.encode(list, keepingUnreadFrom: storedSources)
    }

    /// Expenses that have a deleted category keep it, and if any does it stays in the picker;
    /// it is just never filled in on its own again.
    private func removeCategory(_ category: LabeledIcon) {
        storedCategories = UserCatalog.encode(categories.filter { $0 != category }, keepingUnreadFrom: storedCategories)
        UserCatalog.markDeleted(category.name, true)
        UserCatalog.setColor(nil, for: category.name, key: UserCatalog.categoryColorsKey)
    }

    private func remove(_ source: LabeledIcon) {
        let list = sources.filter { $0 != source }
        storedSources = UserCatalog.encode(list, keepingUnreadFrom: storedSources)
        UserCatalog.setColor(nil, for: source.name, key: UserCatalog.sourceColorsKey)
        if UserCatalog.same(defaultSource, source.name) { defaultSource = list.first?.name ?? "" }
    }
}

/// The names the expenses use, newest first: categories most used first, cards as they come.
/// Only those fields are read from the store.
private struct UsedNames {
    var categories: [String] = []
    var cards: [String] = []

    static func read(in context: ModelContext) -> UsedNames {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.propertiesToFetch = [\.category, \.card, \.date]
        let rows = (try? context.fetch(descriptor)) ?? []
        let history = rows.map { CategorizedExpense(merchant: "", category: $0.category, date: $0.date) }
        return UsedNames(categories: CategoryMemory.known(in: history), cards: rows.compactMap(\.card))
    }
}
