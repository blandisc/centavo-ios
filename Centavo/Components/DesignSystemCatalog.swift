import SwiftUI

/// Every token and component of «Noche ticket» on one scrolling page, for the Xcode canvas.
/// Not reachable from the app: it exists for its `#Preview`s and as a living reference
/// (docs/DESIGN_SYSTEM.md). Add each new token or component here.
struct DesignSystemCatalog: View {
    private static let colors: [(String, Color)] = [
        ("background", Theme.background), ("surface", Theme.surface), ("raised", Theme.raised),
        ("ink", Theme.ink), ("muted", Theme.muted), ("faint", Theme.faint),
        ("brass", Theme.brass), ("brassMid", Theme.brassMid), ("brassLow", Theme.brassLow),
        ("onBrass", Theme.onBrass), ("hairline", Theme.hairline), ("outline", Theme.outline),
        ("dimmed", Theme.dimmed), ("danger", Theme.danger), ("good", Theme.good),
        ("categoryRest", Theme.categoryRest),
    ] + Theme.categories.enumerated().map { ("categories[\($0.offset)]", $0.element) }

    private static let spaces: [(String, CGFloat)] = [
        ("xxxs", Theme.Space.xxxs), ("xxs", Theme.Space.xxs), ("xs", Theme.Space.xs),
        ("s", Theme.Space.s), ("sm", Theme.Space.sm), ("m", Theme.Space.m), ("ml", Theme.Space.ml),
        ("l", Theme.Space.l), ("lx", Theme.Space.lx), ("xl", Theme.Space.xl), ("xlx", Theme.Space.xlx),
        ("xxl", Theme.Space.xxl), ("xxxl", Theme.Space.xxxl),
    ]

    private static let radii: [(String, CGFloat)] = [
        ("bar", Theme.Radius.bar), ("tile", Theme.Radius.tile), ("chip", Theme.Radius.chip),
        ("ticket", Theme.Radius.ticket), ("control", Theme.Radius.control),
        ("panel", Theme.Radius.panel), ("card", Theme.Radius.card),
    ]

    @State private var amount = "1,234.50"
    @State private var name = ""
    @State private var toggle = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                section("Color") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.s), GridItem(.flexible())],
                              alignment: .leading, spacing: Theme.Space.s) {
                        ForEach(Self.colors, id: \.0) { name, color in
                            HStack(spacing: Theme.Space.s) {
                                RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(color)
                                    .frame(width: Theme.Size.rowTile, height: Theme.Size.rowTile)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Theme.Radius.chip)
                                            .strokeBorder(Theme.hairline)
                                    }
                                Text(name).font(.ticket(.hint)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                section("Tipografía · TicketStyle") {
                    ForEach(TicketStyle.allCases, id: \.self) { style in
                        Text(verbatim: "\(style) \(Int(style.size))")
                            .font(.ticket(style))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(Theme.MinimumScale.text)
                    }
                }

                section("Espaciado · Theme.Space") {
                    ForEach(Self.spaces, id: \.0) { name, value in
                        HStack(spacing: Theme.Space.s) {
                            Rectangle().fill(Theme.brass).frame(width: value, height: Theme.Space.m)
                            Text(verbatim: "\(name) \(Int(value))").font(.ticket(.hint))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }

                section("Radios · Theme.Radius") {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(Self.radii, id: \.0) { name, value in
                            VStack(spacing: Theme.Space.xxs) {
                                RoundedRectangle(cornerRadius: value).fill(Theme.surface)
                                    .frame(width: Theme.Size.choiceTile, height: Theme.Size.choiceTile)
                                Text(name).font(.ticket(.micro)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                section("Botones") {
                    Button {} label: { PrimaryButtonLabel("Configurar ahora", systemImage: "wallet.pass") }
                        .ticketProminent()
                    Button {} label: { PrimaryButtonLabel("Borrar", kind: .destructive) }
                        .ticketProminent(.destructive)
                    SecondaryButton("Después") {}
                }

                section("Formas y tarjetas") {
                    Text("Sin gastos todavía").font(.ticket(.bodyStrong)).foregroundStyle(Theme.ink)
                        .padding(Theme.Space.xlx)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ticketOutline(.emphasis)
                    Text("Pesos mexicanos").font(.ticket(.body)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Space.l)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow, alignment: .leading)
                        .selectableCard(selected: true)
                    Text("Panel de nota").font(.ticket(.detail)).foregroundStyle(Theme.muted)
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ticketPanel()
                    Perforation()
                }

                section("Texto") {
                    SectionLabel("Es una devolución")
                    HintText("Pista: puedes cambiarlo después.")
                    NoteText("Nota que explica.")
                    NoteText("Ya tienes uno con ese nombre.", color: Theme.danger)
                    Text("Encabezado de sección").ticketCaption()
                }

                section("Campos y filas") {
                    AmountInputField("Monto", text: $amount, prompt: "0.00")
                    TicketTextField("Comercio", text: $name, prompt: "Oxxo, Uber…")
                    IconRow("BBVA", systemImage: "creditcard")
                    Toggle(isOn: $toggle) { SectionLabel("Se repite") }.tint(Theme.brass)
                    AdaptiveStack {
                        Text("Hoy · 23 oct").font(.ticket(.microStrong)).foregroundStyle(Theme.brass)
                        Text("$1,234.50").font(.ticket(.micro)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title).ticketCaption().accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// The recipe of docs/DESIGN_SYSTEM.md §4, compiled so it never goes stale: a new sheet built
/// only from the design system.
struct RecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var name = ""
    @State private var repeats = false

    private var canSave: Bool { !amount.isEmpty && !name.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInputField("Monto", text: $amount, prompt: "0.00", identifier: "receta-monto")
                    TicketTextField("Nombre", text: $name, prompt: "Renta, gimnasio…",
                                    identifier: "receta-nombre")
                    Toggle(isOn: $repeats) { SectionLabel("Se repite") }
                        .tint(Theme.brass)
                } header: {
                    Text("Gasto").ticketCaption()
                } footer: {
                    HintText("Puedes cambiarlo después en «Más».")
                }
                .listRowBackground(Theme.surface)
                Section {
                    IconRow("Efectivo", systemImage: "banknote")
                } header: {
                    Text("Cómo pagas").ticketCaption()
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Nuevo fijo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.font(.ticket(.footnote))
                }
            }
            .saveBar(canSave ? "\(name) · \(amount)" : "Falta el monto", enabled: canSave) { dismiss() }
        }
    }
}

#Preview("Catálogo") { DesignSystemCatalog().ticketPreview() }

#Preview("Catálogo · AX5") {
    DesignSystemCatalog()
        .ticketPreview()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Receta de hoja") { RecipeSheet().ticketPreview() }
