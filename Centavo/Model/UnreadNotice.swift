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

    /// A notice that couldn't be read. `always`: it read as a charge whose amount still didn't
    /// make it, so it is kept whatever it looks like; otherwise only what looks like a wrong
    /// wiring is (`PendingPayment.unread`).
    ///
    /// `justSaved`: the shops of the Wallet payments saved in the last two minutes. A notice
    /// that brought only a name from one of them is that same payment, told by the other
    /// automation, and is not kept (`PendingPayments.isSettled`).
    static func note(_ text: String, always: Bool = false, justSaved: [String] = [],
                     now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        guard let payment = PendingPayment.unread(text, always: always, date: now),
              !PendingPayments.isSettled(payment, by: justSaved, at: now) else { return }
        add(payment, now: now, defaults: defaults)
    }

    /// A good payment was just saved in `merchants` (as sent and as named): the notice that
    /// brought only that shop's name in the last two minutes was the same payment and goes.
    /// Nothing with a figure or a currency is ever taken away here.
    static func settle(savedIn merchants: [String], now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        let list = PendingPayments.decode(defaults.string(forKey: listKey) ?? "")
        let left = PendingPayments.settling(list, savedIn: merchants, at: now)
        if left != list { write(left, defaults: defaults) }
    }

    /// The shops of the Wallet payments saved in the last two minutes, as sent and as named:
    /// what `note(justSaved:)` compares a name-only notice with.
    static func justSavedShops(in context: ModelContext, now: Date = AppClock.now) -> [String] {
        let since = now.addingTimeInterval(-CaptureGuard.otherSourceWindow)
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since && $0.rawAmount != nil })
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.flatMap { [$0.merchant, $0.displayName ?? ""] }.filter { !$0.isEmpty }
    }

    /// A payment that read and couldn't be saved: what was read of it stays here.
    static func noteUnsaved(amount: String, merchant: String?, card: String?,
                            now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        guard let payment = PendingPayment.unsaved(amount: amount, merchant: merchant, card: card, date: now) else { return }
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

    /// A payment the automation just saved here.
    static func note(amount: String, merchant: String, now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: dateKey)
        defaults.set(PendingPayment.unsaved(amount: amount, merchant: merchant, card: nil, date: now)?.text ?? "",
                     forKey: textKey)
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
        for key in [dateKey, textKey, sessionKey] { defaults.removeObject(forKey: key) }
    }

    /// A stored moment; 0 is «never».
    private static func date(_ stored: Double) -> Date? {
        stored > 0 ? Date(timeIntervalSinceReferenceDate: stored) : nil
    }
}
