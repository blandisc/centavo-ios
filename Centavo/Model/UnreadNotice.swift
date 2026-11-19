import CentavoCore
import Foundation
import SwiftData

/// The Wallet payments the capture received and couldn't write down, kept for «Hoy» to say so
/// instead of the payment vanishing (`PendingPayment`):
/// - a notice that arrived without an amount, as when «Notificación» is set to «Subtítulo» in
///   Atajos and only the merchant arrives (seen on the owner's iPhone, 2026-10-21);
/// - a payment that read, when the app couldn't open or save its expenses (2026-11-11).
///
/// A list, in `UserDefaults` and not in the store, so it is still there when the store is
/// what failed. Only the person empties it, one by one or all at once: a payment that comes in
/// right after no longer clears it (it did until 2026-11-11, and the first one was lost).
enum UnreadNotice {
    /// The list, as JSON text. Under «respaldo.»: those keys neither go into a backup nor are
    /// replaced when one is restored (`DailyBackup.Settings.isOurs`), and what this iPhone
    /// couldn't save must not be swapped for what another day's backup had pending.
    static let listKey = "respaldo.pagosPendientes"

    /// Before the list (until 2026-11-11) there was one notice only; `prepare` carries it over.
    static let textKey = "unreadWalletNotice"
    static let dateKey = "unreadWalletNoticeDate"

    /// The Wallet payments that already took a name-only notice as their own in the last two
    /// minutes (`NoticePairing`), as JSON text, so each takes one only (2026-11-19). Under
    /// «respaldo.», like the list: it is about this iPhone's captures, not for a backup.
    static let pairedKey = "respaldo.avisosEmparejados"

    /// A notice that couldn't be read. `always`: it read as a charge whose amount still didn't
    /// make it, so it is kept whatever it looks like; otherwise only what looks like a wrong
    /// wiring is (`PendingPayment.unread`).
    ///
    /// `justSaved`: the shops of each Wallet payment saved in the last two minutes. A notice
    /// that brought only a name from one of them is that same payment, told by the other
    /// automation, and is not kept, unless that payment already took one (2026-11-19: the
    /// second purchase at the same shop was lost; `PendingPayments.isSettled`).
    static func note(_ text: String, always: Bool = false, justSaved: [[String]] = [],
                     now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        guard let payment = PendingPayment.unread(text, always: always, date: now) else { return }
        let paired = pairings(defaults: defaults)
        guard PendingPayments.isSettled(payment, among: justSaved, paired: paired, at: now),
              let shops = justSaved.first(where: { PendingPayments.isSettled(payment, by: $0, at: now) }) else {
            add(payment, now: now, defaults: defaults)
            return
        }
        let pairing = NoticePairing(shops: shops, date: now)
        writePairings(PendingPayments.pairings(paired, adding: pairing, at: now), defaults: defaults)
    }

    /// A good payment was just saved in `merchants` (as sent and as named): the notice that
    /// brought only that shop's name in the last two minutes was the same payment and goes,
    /// one at most, and the payment counts as paired. Nothing with a figure or a currency is
    /// ever taken away here.
    static func settle(savedIn merchants: [String], now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        let list = PendingPayments.decode(defaults.string(forKey: listKey) ?? "")
        let left = PendingPayments.settling(list, savedIn: merchants, at: now)
        guard left != list else { return }
        write(left, defaults: defaults)
        let pairing = NoticePairing(shops: merchants.filter { !$0.isEmpty }, date: now)
        writePairings(PendingPayments.pairings(pairings(defaults: defaults), adding: pairing, at: now),
                      defaults: defaults)
    }

    /// The shops of each Wallet payment saved in the last two minutes, as sent and as named:
    /// what `note(justSaved:)` compares a name-only notice with, one entry per payment.
    static func justSavedShops(in context: ModelContext, now: Date = AppClock.now) -> [[String]] {
        let since = now.addingTimeInterval(-CaptureGuard.otherSourceWindow)
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since && $0.rawAmount != nil })
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { row in [row.merchant, row.displayName ?? ""].filter { !$0.isEmpty } }
    }

    private static func pairings(defaults: UserDefaults) -> [NoticePairing] {
        LenientList.decode(NoticePairing.self, from: defaults.string(forKey: pairedKey) ?? "").items
    }

    private static func writePairings(_ list: [NoticePairing], defaults: UserDefaults) {
        if list.isEmpty {
            defaults.removeObject(forKey: pairedKey)
        } else {
            defaults.set(LenientList.encode(list), forKey: pairedKey)
        }
    }

    /// A payment that read and couldn't be saved: what was read of it stays here.
    static func noteUnsaved(amount: String, merchant: String?, card: String?, spentOn: Date? = nil,
                            now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        guard let payment = PendingPayment.unsaved(amount: amount, merchant: merchant, card: card, date: now,
                                                   spentOn: spentOn) else { return }
        add(payment, now: now, defaults: defaults)
    }

    /// What is waiting, newest first, from the text `@AppStorage(listKey)` hands a view.
    static func pending(stored: String, now: Date = AppClock.now) -> [PendingPayment] {
        PendingPayments.current(PendingPayments.decode(stored), now: now)
    }

    static func pending(now: Date = AppClock.now, defaults: UserDefaults = .standard) -> [PendingPayment] {
        pending(stored: defaults.string(forKey: listKey) ?? "", now: now)
    }

    /// The person wrote it down or discarded it.
    static func remove(_ id: UUID, defaults: UserDefaults = .standard) {
        let list = PendingPayments.decode(defaults.string(forKey: listKey) ?? "")
        write(PendingPayments.removing(id, from: list), defaults: defaults)
    }

    /// «Descartar todos».
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: listKey)
    }

    /// Once per launch, before «Hoy» reads the list.
    @MainActor static func prepare(now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        guard !prepared else { return }
        prepared = true
        #if DEBUG
        prepareDemo(now: now, defaults: defaults)
        #endif
        carryOverSingleNotice(now: now, defaults: defaults)
    }

    /// The single notice of earlier versions joins the list, if it was still showing (two days,
    /// as then), and its keys go.
    static func carryOverSingleNotice(now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        guard let text = defaults.string(forKey: textKey) else { return }
        let date = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: dateKey))
        defaults.removeObject(forKey: textKey)
        defaults.removeObject(forKey: dateKey)
        guard now.timeIntervalSince(date) < legacyLife, date <= now,
              let payment = PendingPayment.unread(text, always: true, date: date) else { return }
        add(payment, now: now, defaults: defaults)
    }

    @MainActor private static var prepared = false

    /// How long the single notice of earlier versions stayed on screen.
    private static let legacyLife: TimeInterval = 2 * 24 * 3600

    private static func add(_ payment: PendingPayment, now: Date, defaults: UserDefaults) {
        let list = PendingPayments.decode(defaults.string(forKey: listKey) ?? "")
        write(PendingPayments.adding(payment, to: list, now: now), defaults: defaults)
    }

    private static func write(_ list: [PendingPayment], defaults: UserDefaults) {
        if list.isEmpty {
            defaults.removeObject(forKey: listKey)
        } else {
            defaults.set(PendingPayments.encode(list), forKey: listKey)
        }
    }

    #if DEBUG
    /// The demos the screen tests open start clean, like their in-memory store: what an earlier
    /// run left pending or proven would leak into this one. `-centavo-pendientes` leaves two
    /// payments waiting (one unread, one unsaved), to see and test the notice on «Hoy».
    private static func prepareDemo(now: Date, defaults: UserDefaults) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-centavo-demo") }) || arguments.contains("-centavo-empty") else { return }
        clear(defaults: defaults)
        defaults.removeObject(forKey: pairedKey)
        defaults.removeObject(forKey: textKey)
        defaults.removeObject(forKey: dateKey)
        CaptureArrival.forget(defaults: defaults)
        guard arguments.contains("-centavo-pendientes") else { return }
        note("Google", now: now.addingTimeInterval(-2 * 3600), defaults: defaults)
        noteUnsaved(amount: "$319.00", merchant: "Liverpool", card: "BBVA", now: now.addingTimeInterval(-600), defaults: defaults)
    }
    #endif
}

/// What only this iPhone knows about the automation: when it last delivered a payment here, and
/// when the setup guide was opened. The guide says «Ya funciona» from these alone
/// (`CaptureProof`), never from the expenses, which may have come in a restored backup or from
/// another device through iCloud.
///
/// Under «respaldo.», the keys a backup neither carries nor replaces
/// (`DailyBackup.Settings.isOurs`): a restored backup can't bring a proof with it.
enum CaptureArrival {
    /// When the automation last saved a payment on this iPhone (seconds since 2001).
    static let dateKey = "respaldo.esteIPhone.walletLlego"
    /// That payment, as the guide says it: «$47.50 en Oxxo».
    static let textKey = "respaldo.esteIPhone.walletLlegoTexto"
    /// When the guide was opened for the setup under way (seconds since 2001).
    static let sessionKey = "respaldo.esteIPhone.guiaAbierta"
    /// When the automation delivered its very first payment here (seconds since 2001): «Hoy»
    /// says «Llegó tu primer pago solo» for a day (2026-11-18). Never set for whoever already
    /// had payments arriving before it existed.
    static let firstKey = "respaldo.esteIPhone.walletPrimero"
    /// That first payment, as «Hoy» says it (2026-11-18): `textKey` is the latest one, and
    /// with a few payments that first day the card named the last, maybe a refund.
    static let firstTextKey = "respaldo.esteIPhone.walletPrimeroTexto"
    /// The parts of those two payments, put together when read (`latestText`, `firstText`), so
    /// they follow the iPhone's language (2026-11-18). The `…Texto` keys stay written for what
    /// reads them still, and as what earlier versions left.
    static let amountKey = "respaldo.esteIPhone.walletLlegoMonto"
    static let merchantKey = "respaldo.esteIPhone.walletLlegoComercio"
    static let firstAmountKey = "respaldo.esteIPhone.walletPrimeroMonto"
    static let firstMerchantKey = "respaldo.esteIPhone.walletPrimeroComercio"

    /// Whether Wallet had ever delivered a payment here (`WalletWatch.lastArrivalKey`), as
    /// `note(arrivedBefore:)` takes it: asked before `ExpenseRecorder.record`, which marks the
    /// payment it saves as arrived (2026-11-18: asked after, the first one never counted).
    static func walletKnown(defaults: UserDefaults = .standard) -> Bool {
        defaults.double(forKey: WalletWatch.lastArrivalKey) > 0
    }

    /// A payment the automation just saved here. `arrivedBefore`: `walletKnown()` before it
    /// was saved; `nil` reads it now (the guide's demo, which saves nothing).
    static func note(amount: String, merchant: String, arrivedBefore: Bool? = nil,
                     now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        let payment = PendingPayment.unsaved(amount: amount, merchant: merchant, card: nil, date: now)
        let text = payment?.text ?? ""
        let known = arrivedBefore ?? walletKnown(defaults: defaults)
        if defaults.double(forKey: dateKey) <= 0, defaults.double(forKey: firstKey) <= 0, !known {
            defaults.set(now.timeIntervalSinceReferenceDate, forKey: firstKey)
            defaults.set(text, forKey: firstTextKey)
            keep(payment, amountKey: firstAmountKey, merchantKey: firstMerchantKey, defaults: defaults)
        }
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: dateKey)
        defaults.set(text, forKey: textKey)
        keep(payment, amountKey: amountKey, merchantKey: merchantKey, defaults: defaults)
    }

    /// The latest payment, as the guide says it now: «$47.50 en Oxxo», «$47.50 at Oxxo».
    static func latestText(defaults: UserDefaults = .standard) -> String {
        composed(amountKey: amountKey, merchantKey: merchantKey, fallback: textKey, defaults: defaults)
    }

    /// The first payment, as «Hoy» says it now. Empty for a first one kept with no text.
    static func firstText(defaults: UserDefaults = .standard) -> String {
        composed(amountKey: firstAmountKey, merchantKey: firstMerchantKey, fallback: firstTextKey, defaults: defaults)
    }

    /// Both parts or none: a payment with only one of them is written as it was kept.
    private static func keep(_ payment: PendingPayment?, amountKey: String, merchantKey: String,
                             defaults: UserDefaults) {
        guard let amount = payment?.amount, let merchant = payment?.merchant else {
            defaults.removeObject(forKey: amountKey)
            defaults.removeObject(forKey: merchantKey)
            return
        }
        defaults.set(amount, forKey: amountKey)
        defaults.set(merchant, forKey: merchantKey)
    }

    private static func composed(amountKey: String, merchantKey: String, fallback: String,
                             defaults: UserDefaults) -> String {
        guard let amount = defaults.string(forKey: amountKey),
              let merchant = defaults.string(forKey: merchantKey) else {
            return defaults.string(forKey: fallback) ?? ""
        }
        return PendingPayment.line(amount: amount, merchant: Expense.shownMerchant(merchant))
    }

    /// The guide was opened («Configurar», «Revisar», the warning on «Hoy»): the setup under
    /// way carries on, or a new one starts (`CaptureProof.sessionStart`).
    static func openGuide(now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        let start = CaptureProof.sessionStart(previous: date(defaults.double(forKey: sessionKey)),
                                              arrivedHere: date(defaults.double(forKey: dateKey)), now: now)
        defaults.set(start.timeIntervalSinceReferenceDate, forKey: sessionKey)
    }

    /// What the guide can say now. `lastKnown`: the newest Wallet payment among the expenses.
    static func proof(session: Double, arrived: Double, lastKnown: Date?, now: Date = AppClock.now) -> CaptureProof {
        CaptureProof(sessionStart: date(session), arrivedHere: date(arrived), lastKnown: lastKnown, now: now)
    }

    static func forget(defaults: UserDefaults = .standard) {
        let keys = [dateKey, textKey, sessionKey, firstKey, firstTextKey,
                    amountKey, merchantKey, firstAmountKey, firstMerchantKey]
        for key in keys { defaults.removeObject(forKey: key) }
    }

    /// What «Hoy» and Ajustes say about the automation, from the stored moments.
    static func health(lastCapture: Date?, session: Double, first: Double, now: Date) -> CaptureHealth {
        CaptureHealth(lastCapture: lastCapture, now: now, guideOpened: date(session), firstArrival: date(first))
    }

    /// A stored moment; 0 is «never».
    static func date(_ stored: Double) -> Date? {
        stored > 0 ? Date(timeIntervalSinceReferenceDate: stored) : nil
    }
}
