import CentavoCore
import SwiftData
import SwiftUI

/// «Tarjetas y categorías»: the ways someone pays (one of them the default for what they
/// write down by hand) and the categories of their own, each with its icon.
struct CatalogSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserCatalog.sourcesKey) private var storedSources = ""
    @AppStorage(UserCatalog.defaultSourceKey) private var defaultSource = ""
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var storedHidden = ""
    @Query private var expenses: [Expense]
    @State private var editing: Editing?

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

    private func shows(_ name: String) -> Binding<Bool> {
        Binding(get: { !hidden.contains { UserCatalog.same($0, name) } }, set: { show in
            var list = hidden.filter { !UserCatalog.same($0, name) }
            if !show { list.append(name) }
            storedHidden = UserCatalog.encodeNames(list)
        })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sources) { source in
                        Button { editing = .source(source) } label: {
                            row(source, isDefault: UserCatalog.same(source.name, defaultSource))
                        }
                        .swipeActions(edge: .leading) {
                            Button("Predeterminada", systemImage: "star") { defaultSource = source.name }
                                .tint(Theme.brass)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Borrar", systemImage: "trash", role: .destructive) { remove(source) }
                        }
                        .contextMenu {
                            Button("Usar por defecto", systemImage: "star") { defaultSource = source.name }
                            Button("Borrar", systemImage: "trash", role: .destructive) { remove(source) }
                        }
                    }
                    addButton("Agregar tarjeta o efectivo", identifier: "agregar-fuente") {
                        editing = .source(nil)
                    }
                } header: {
                    Text("Cómo pagas").ticketCaption()
                } footer: {
                    hint(sources.isEmpty
                         ? "Agrega tus tarjetas y el efectivo. La predeterminada ya viene elegida cuando anotas a mano."
                         : "La de la estrella ya viene elegida cuando anotas a mano: desliza a la derecha para cambiarla. Toca una para borrarla.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(categories) { category in
                        Button { editing = .category(category) } label: { row(category, isDefault: false) }
                            .swipeActions(edge: .trailing) {
                                Button("Borrar", systemImage: "trash", role: .destructive) {
                                    removeCategory(category)
                                }
                            }
                    }
                    addButton("Nueva categoría", identifier: "agregar-categoria") { editing = .category(nil) }
                } header: {
                    Text("Tus categorías").ticketCaption()
                } footer: {
                    hint("Toca una para cambiarla o borrarla; también puedes deslizarla a la izquierda. Borrar una no cambia los gastos que ya la tienen.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(others, id: \.self) { name in
                        Toggle(isOn: shows(name)) {
                            HStack(spacing: 12) {
                                Image(systemName: CategoryStyle.icon(for: name, custom: categories))
                                    .foregroundStyle(Theme.brass)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                Text(name)
                                    .font(.ticket(15, relativeTo: .body))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .tint(Theme.brass)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("mostrar-\(name)")
                    }
                } header: {
                    Text("Categorías de siempre").ticketCaption()
                } footer: {
                    hint("Apaga las que no uses y ya no saldrán al anotar. Los gastos que ya la tienen no cambian.")
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Tarjetas y categorías")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                }
            }
            .sheet(item: $editing) { item in
                switch item {
                case .source(let source):
                    LabeledIconSheet(title: source == nil ? "Nueva tarjeta" : "Editar tarjeta",
                                     prompt: "BBVA, Nu, Efectivo…", icons: UserCatalog.sourceIcons,
                                     taken: sources.map(\.name), initial: source,
                                     onDelete: source.map { item in { remove(item) } }) { saved in
                        save(saved, replacing: source)
                    }
                case .category(let category):
                    LabeledIconSheet(title: category == nil ? "Nueva categoría" : "Editar categoría",
                                     prompt: "Mascotas, Gimnasio…", icons: UserCatalog.categoryIcons,
                                     taken: categories.map(\.name) + CategoryStyle.common.map(\.name),
                                     initial: category,
                                     onDelete: category.map { item in { removeCategory(item) } }) { saved in
                        var list = categories
                        if let category, let index = list.firstIndex(of: category) {
                            list[index] = saved
                            UserCatalog.renameCategory(category.name, to: saved.name)
                        } else { list.append(saved) }
                        storedCategories = UserCatalog.encode(list)
                        storedHidden = UserCatalog.hiddenNames(storedHidden, setting: saved.name, hidden: false)
                    }
                }
            }
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

    /// A deleted category also leaves the picker and is never filled in on its own again;
    /// expenses that have it keep it. If it was used, it shows off in «Categorías de siempre».
    private func removeCategory(_ category: LabeledIcon) {
        storedCategories = UserCatalog.encode(categories.filter { $0 != category })
        storedHidden = UserCatalog.hiddenNames(storedHidden, setting: category.name, hidden: true)
    }

    private func remove(_ source: LabeledIcon) {
        let list = sources.filter { $0 != source }
        storedSources = UserCatalog.encode(list)
        if UserCatalog.same(defaultSource, source.name) { defaultSource = list.first?.name ?? "" }
    }

    private func row(_ item: LabeledIcon, isDefault: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .foregroundStyle(Theme.brass)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(item.name)
                .font(.ticket(15, relativeTo: .body))
                .foregroundStyle(Theme.ink)
            Spacer()
            if isDefault {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.brass)
                    .accessibilityLabel("Predeterminada")
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func addButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.brass)
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier(identifier)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.ticket(12, relativeTo: .footnote)).foregroundStyle(Theme.muted)
    }
}
