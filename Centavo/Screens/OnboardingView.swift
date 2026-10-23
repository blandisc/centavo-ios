import CentavoCore
import SwiftData
import SwiftUI

/// The first time Al día opens empty: what it does, the currency, the budget, the fixed
/// expenses and the Wallet automation, one short page each. Every page can be skipped.
///
/// Each page reads the same way: a brass emblem, a «Paso X de 5» caption, a title, a short
/// lead and the content; the dots between the bottom-bar buttons show where the person is.
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

    /// How far the dot row slides toward its side to look centered (see the carousel).
    private var stepDotShift: CGFloat {
        page < pages / 2 ? Theme.Size.pageDotShift : -Theme.Size.pageDotShift
    }

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
                    StepDots(current: page, of: pages)
                        // The «Paso X de 5» caption above each title carries the progress.
                        .accessibilityHidden(true)
                        // The lit pill is wider than the dot, so centering the five slots left
                        // the current one off the middle (measured): shift it toward its side.
                        .offset(x: stepDotShift)
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
        page(title: "Al día", symbol: "wallet.pass.fill",
             lead: "Te dice cuánto puedes gastar hoy, sin que anotes nada.") {
            VStack(spacing: Theme.Space.none) {
                point("wallet.pass", "Cada compra con Wallet se anota sola: en línea o acercando el teléfono.")
                pointDivider
                point("calendar", "Reparte tu presupuesto entre los días que quedan del mes.")
                pointDivider
                point("lock", "Sin cuenta ni servidor: tus gastos viven en tu iPhone y en tu iCloud.")
            }
            .padding(.horizontal, Theme.Space.ml)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ticketPanel()
        }
    }

    private var currencyPage: some View {
        page(title: "Tu moneda", symbol: "banknote",
             lead: "La moneda en la que sumas tu mes. Lo que llegue en otra se muestra aparte.") {
            VStack(spacing: Theme.Space.s) {
                ForEach(CurrencyPreference.offered, id: \.self) { code in
                    Button {
                        currency = code
                    } label: {
                        IconRow(CurrencyPreference.name(code),
                                systemImage: CashSymbol.symbol(for: code)) {
                            if currency == code {
                                Image(systemName: "checkmark")
                                    .font(Theme.Symbol.regular)
                                    .foregroundStyle(Theme.brass)
                            }
                        }
                        .padding(.horizontal, Theme.Space.l)
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
        page(title: "Tu presupuesto", symbol: "target",
             lead: "Cuánto quieres gastar al mes. Con eso, Al día te dice cuánto puedes gastar hoy.") {
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
        page(title: "Gastos fijos", symbol: "repeat",
             lead: "La renta, la luz y las suscripciones se anotan cada mes, sin que hagas nada.") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if !fixed.isEmpty {
                    VStack(spacing: Theme.Space.none) {
                        ForEach(Array(fixed.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { pointDivider }
                            fixedRow(item)
                        }
                    }
                    .padding(.horizontal, Theme.Space.ml)
                    .padding(.vertical, Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ticketPanel()
                }
                VStack(spacing: Theme.Space.s) {
                    TextField("Qué es", text: $draftName,
                              prompt: Text("Renta, Netflix…").foregroundStyle(Theme.faint))
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .accessibilityIdentifier("bienvenida-fijo-nombre")
                    Divider().overlay(Theme.hairline)
                    TextField("Cuánto", text: $draftAmount,
                              prompt: Text("Monto").foregroundStyle(Theme.faint))
                        .keyboardType(.decimalPad)
                        .focused($focused, equals: .amount)
                        .groupsThousands($draftAmount)
                        .accessibilityIdentifier("bienvenida-fijo-monto")
                    Divider().overlay(Theme.hairline)
                    Stepper("El día \(draftDay) de cada mes", value: $draftDay, in: 1...31)
                        .foregroundStyle(Theme.ink)
                }
                .font(.ticket(.field))
                .padding(Theme.Space.ml)
                .selectableCard(selected: false)
                Button(action: addFixed) {
                    Label("Agregar", systemImage: "plus")
                        .font(.ticket(.footnoteStrong))
                        .tracking(Theme.Tracking.action)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.brass)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(draftValue == nil
                          || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("bienvenida-fijo-agregar")
                NoteText("También puedes marcar como fijo cualquier gasto que ya anotaste.",
                         color: Theme.faint)
            }
        }
    }

    private var walletPage: some View {
        page(title: "Conecta Wallet", symbol: "wallet.pass",
             lead: "Una automatización de Atajos avisa a Al día de cada compra. Se configura una vez y toma unos minutos.") {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Button {
                    save(); finish(true)
                } label: {
                    PrimaryButtonLabel("Configurar ahora", systemImage: "wallet.pass")
                }
                .ticketProminent()
                .accessibilityIdentifier("bienvenida-configurar")
                SecondaryButton("Después", identifier: "bienvenida-despues") { save(); finish(false) }
                HintText("Si lo dejas para después, lo encuentras en «Más › Configurar atajo».")
            }
        }
    }

    // MARK: Pieces

    /// Every page's shell: an emblem, a step caption, the title and lead, then the content,
    /// with the shallow margins the design system asks for a non-form screen.
    private func page<Content: View>(title: String, symbol: String, lead: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                OnboardingEmblem(systemImage: symbol)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Paso \(page + 1) de \(pages)").ticketCaption()
                    Text(title)
                        .font(.ticket(.pageTitle))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
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

    private var pointDivider: some View {
        Divider()
            .overlay(Theme.hairline)
            .padding(.vertical, Theme.Space.xxs)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: icon).foregroundStyle(Theme.brass).frame(width: pointIconWidth)
            Text(text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .font(.ticket(.callout))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fixedRow(_ item: FixedDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(item.name)
                .font(.ticket(.bodyMedium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(item.amount.formatted(.number.precision(.fractionLength(0...2)))) · día \(item.day)")
                .font(.ticket(.footnote))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Space.xxs)
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

/// The brass symbol on a raised, hairline-edged tile that heads each page: the page's best
/// one-word picture. Decorative: VoiceOver reads the title that follows, not the symbol.
private struct OnboardingEmblem: View {
    let systemImage: String
    @ScaledMetric(relativeTo: .body) private var tile = Theme.Size.onboardingEmblem

    var body: some View {
        Image(systemName: systemImage)
            .font(Theme.Symbol.large)
            .foregroundStyle(Theme.brass)
            .frame(width: tile, height: tile)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.hairline)
            }
            .accessibilityHidden(true)
    }
}

/// The bottom-bar progress: one pill per page, the current one longer, like the carousel's
/// dots. The «Paso X de 5» caption above the title carries the progress for VoiceOver.
private struct StepDots: View {
    let current: Int
    let of: Int

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(0..<of, id: \.self) { index in
                Capsule()
                    .fill(current == index ? Theme.ink : Theme.dimmed)
                    .frame(width: current == index ? Theme.Size.pageDotCurrent : Theme.Size.pageDot,
                           height: Theme.Size.pageDot)
            }
        }
    }
}

/// The SF Symbol of each offered currency, so the choice reads without reading.
private enum CashSymbol {
    static func symbol(for code: String) -> String {
        switch code {
        case "MXN": "mexicanpesosign"
        case "USD": "dollarsign"
        case "EUR": "eurosign"
        default: "banknote"
        }
    }
}

private struct FixedDraft: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let day: Int
}