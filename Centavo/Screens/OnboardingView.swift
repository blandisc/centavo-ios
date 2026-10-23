import CentavoCore
import SwiftData
import SwiftUI

/// The first time Al día opens empty: what it does, the currency, the budget, the fixed
/// expenses and the Wallet automation, one short page each. Every page can be skipped.
struct OnboardingView: View {
    /// Called when it is done; `openGuide` asks for the Wallet guide right after.
    let finish: (_ openGuide: Bool) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    @State private var page = 0
    /// Which way the last move went, so the pages slide the right way.
    @State private var forward = true
    @State private var currency = CurrencyPreference.current
    @State private var budgetText = ""
    @State private var fixed: [FixedDraft] = []
    @State private var draftName = ""
    @State private var draftAmount = ""
    @State private var draftDay = 1
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var pointIconWidth = Theme.Size.iconColumnNarrow

    private enum Field { case budget, name, amount }
    private let pages = 5

    var body: some View {
        NavigationStack {
            // One page at a time, moved only by the buttons. A swipeable TabView let a tap in
            // the middle of its animation leave it on one page while the counter said another.
            Group {
                switch page {
                case 0: welcome
                case 1: currencyPage
                case 2: budgetPage
                case 3: fixedPage
                default: walletPage
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Bienvenida")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if page < pages - 1 {
                        Button("Omitir") { save(); finish(false) }
                            .font(.ticket(.footnote))
                            .accessibilityIdentifier("bienvenida-omitir")
                    }
                }
                // The number pad has no return key and covers the bottom bar.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Siguiente") {
                        focused = nil
                        go(to: page + 1)
                    }
                    .font(.ticket(.footnoteStrong))
                    .accessibilityIdentifier("teclado-siguiente")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Anterior", systemImage: "chevron.left") {
                        focused = nil
                        go(to: page - 1)
                    }
                        .disabled(page == 0)
                    Spacer()
                    Text("\(page + 1) de \(pages)")
                        .font(.ticket(.bodyMedium))
                        .tracking(Theme.Tracking.title)
                        .textCase(.uppercase)
                        .fixedSize()
                        .padding(.horizontal, Theme.Space.ml)
                        .accessibilityLabel("Paso \(page + 1) de \(pages)")
                    Spacer()
                    Button("Siguiente", systemImage: "chevron.right") {
                        focused = nil
                        go(to: page + 1)
                    }
                    .disabled(page == pages - 1)
                    .accessibilityIdentifier("bienvenida-siguiente")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func go(to target: Int) {
        guard (0..<pages).contains(target), target != page else { return }
        forward = target > page
        withAnimation(Theme.Motion.page) { page = target }
    }

    // MARK: Pages

    private var welcome: some View {
        pageLayout(title: "Al día", lead: "Te dice cuánto puedes gastar hoy, sin que tengas que anotar nada.") {
            VStack(alignment: .leading, spacing: Theme.Space.ml) {
                point("wallet.pass", "Cada compra con Wallet se anota sola: en línea o acercando el teléfono.")
                point("calendar", "Reparte tu presupuesto entre los días que quedan del mes.")
                point("lock", "Sin cuenta ni servidor: tus gastos viven en tu iPhone y en tu iCloud.")
            }
        }
    }

    private var currencyPage: some View {
        pageLayout(title: "Tu moneda", lead: "En la que sumas el mes. Lo demás se muestra aparte.") {
            VStack(spacing: Theme.Space.s) {
                ForEach(CurrencyPreference.offered, id: \.self) { code in
                    Button {
                        currency = code
                    } label: {
                        HStack {
                            Text(CurrencyPreference.name(code)).foregroundStyle(Theme.ink)
                            Spacer()
                            if currency == code {
                                Image(systemName: "checkmark").foregroundStyle(Theme.brass)
                            }
                        }
                        .font(.ticket(.body))
                        .padding(.horizontal, Theme.Space.l)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow)
                        .selectableCard(selected: currency == code)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moneda-\(code)")
                    .accessibilityAddTraits(currency == code ? .isSelected : [])
                }
            }
        }
    }

    private var budgetPage: some View {
        pageLayout(title: "Tu presupuesto", lead: "¿Cuánto quieres gastar al mes? Con esto te dice cuánto puedes gastar hoy.") {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                AmountInputField("Presupuesto", text: $budgetText, prompt: "8000", size: .compact,
                                 identifier: "bienvenida-presupuesto")
                    .focused($focused, equals: .budget)
                    .padding(Theme.Space.ml)
                    .selectableCard(selected: false)
                if let value = AmountParser.parse(budgetText)?.value, value > 0 {
                    Text(BudgetStore.dailyPreview(value, currency: currency))
                        .font(.ticket(.footnote))
                        .foregroundStyle(Theme.brass)
                        .contentTransition(.numericText())
                        .animation(Theme.Motion.quick, value: budgetText)
                } else {
                    NoteText("Puedes dejarlo vacío y fijarlo después en «Más».", color: Theme.faint)
                }
            }
        }
    }

    private var fixedPage: some View {
        pageLayout(title: "Gastos fijos", lead: "Renta, suscripciones, la luz: se anotan solos cada mes.") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(fixed) { item in
                    HStack {
                        Text(item.name).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(item.amount.formatted(.number.precision(.fractionLength(0...2)))) · día \(item.day)")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.ticket(.footnote))
                    .padding(Theme.Space.m)
                    .ticketPanel()
                }
                VStack(spacing: Theme.Space.s) {
                    TextField("Qué es", text: $draftName, prompt: Text("Renta, Netflix…").foregroundStyle(Theme.faint))
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .accessibilityIdentifier("bienvenida-fijo-nombre")
                    Divider().overlay(Theme.hairline)
                    TextField("Cuánto", text: $draftAmount, prompt: Text("Monto").foregroundStyle(Theme.faint))
                        .keyboardType(.decimalPad)
                        .focused($focused, equals: .amount)
                        .groupsThousands($draftAmount)
                        .accessibilityIdentifier("bienvenida-fijo-monto")
                    Divider().overlay(Theme.hairline)
                    Stepper("El día \(draftDay) de cada mes", value: $draftDay, in: 1...31)
                        .foregroundStyle(Theme.ink)
                }
                .font(.ticket(.body))
                .padding(Theme.Space.ml)
                .selectableCard(selected: false)
                Button("Agregar", systemImage: "plus", action: addFixed)
                    .font(.ticket(.footnoteStrong))
                    .disabled(draftValue == nil || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("bienvenida-fijo-agregar")
                NoteText("También puedes marcar cualquier gasto como fijo después.", color: Theme.faint)
            }
        }
    }

    private var walletPage: some View {
        pageLayout(title: "Conecta Wallet", lead: "Una automatización de Atajos le avisa a Al día de cada compra. Se hace una vez y toma unos minutos.") {
            VStack(spacing: Theme.Space.m) {
                Button {
                    save(); finish(true)
                } label: {
                    PrimaryButtonLabel("Configurar ahora", systemImage: "wallet.pass")
                }
                .ticketProminent()
                .accessibilityIdentifier("bienvenida-configurar")
                SecondaryButton("Después", identifier: "bienvenida-despues") { save(); finish(false) }
            }
        }
    }

    // MARK: Pieces

    private func pageLayout<Content: View>(title: String, lead: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(title)
                    .font(.ticket(.pageTitle))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(lead)
                    .font(.ticket(.body))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: icon).foregroundStyle(Theme.brass).frame(width: pointIconWidth)
            Text(text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .font(.ticket(.callout))
    }

    // MARK: Saving

    private var draftValue: Decimal? {
        guard let value = AmountParser.parse(draftAmount)?.value, value > 0 else { return nil }
        return value
    }

    private func addFixed() {
        guard let value = draftValue else { return }
        fixed.append(FixedDraft(name: draftName.trimmingCharacters(in: .whitespaces),
                                amount: value, day: draftDay))
        draftName = ""; draftAmount = ""; draftDay = 1
        focused = .name
    }

    /// Whatever was filled in is kept, even when the rest is skipped.
    private func save() {
        // A fixed expense typed in but never «Agregar»-ed still counts.
        if draftValue != nil, !draftName.trimmingCharacters(in: .whitespaces).isEmpty { addFixed() }
        storedCurrency = currency
        if let value = AmountParser.parse(budgetText)?.value, value > 0 {
            storedBudget = BudgetStore.stored(value)
        }
        for item in fixed {
            let date = RecurringSchedule.firstDate(day: item.day, now: .now)
            let expense = Expense(amount: item.amount, currencyMarker: currency, merchant: item.name,
                                  date: date, category: MerchantCatalog.category(for: item.name))
            expense.repeatsMonthly = true
            expense.repeatsThrough = date
            expense.repeatDay = item.day
            context.insert(expense)
        }
        try? context.save()
    }
}

private struct FixedDraft: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let day: Int
}
