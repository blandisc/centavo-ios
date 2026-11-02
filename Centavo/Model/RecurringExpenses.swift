import CentavoCore
import Foundation
import SwiftData

/// Logs the copy of every fixed expense whose day already came, at whatever it repeats
/// (`RepeatRule`), and starts the fixed expenses whose first charge just arrived.
enum RecurringExpenses {
    /// Safe to call often (launch, coming back to the app): it only writes what is due.
    @discardableResult
    static func logDue(in context: ModelContext, now: Date = .now,
                       calendar: Calendar = .current) throws -> Int {
        let (started, startedPlans) = try start(dueBy: now, in: context, calendar: calendar)
        var originals = try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.repeatsMonthly == true }
        ))
        var changed = false
        // Each original gets its own id the first time, so two that look the same («Colegio»,
        // $5,000 twice) each log their copy.
        for original in originals where original.fixedID == nil {
            original.fixedID = UUID().uuidString
            changed = true
        }
        // Two originals with one id (a plan two devices started before iCloud brought the
        // other's) leave one, the same on every device, carrying the furthest progress.
        let gone = resolveTwins(originals, in: context)
        if !gone.isEmpty {
            originals.removeAll { gone.contains(ObjectIdentifier($0)) }
            changed = true
        }
        let ids = Set(originals.compactMap(\.fixedID))
        let copies = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.isRepeat == true },
                                                                sortBy: [SortDescriptor(\.date)]))
        // A copy is known by its original and its exact day. Two of the same (another device on
        // the same iCloud logged it before `repeatsThrough` synced here) leave one.
        var logged = started
        var existing = Set<String>()
        var legacy: [Expense] = []
        // Every device must keep the same one, or each keeps its own, deletes the other and
        // the charge is gone: the tie is broken by the copy's own id, which travels with it.
        let ordered = copies.sorted { ($0.date, $0.fixedID ?? "") < ($1.date, $1.fixedID ?? "") }
        for copy in ordered {
            guard let of = copy.fixedOf, ids.contains(of) else { legacy.append(copy); continue }
            if existing.insert(key(of, copy.date)).inserted { continue }
            context.delete(copy)
            changed = true
        }
        // Copies from before ids (or from an original whose id came from another device) are
        // matched by merchant, amount and period, each one used up by a single original.
        func period(_ date: Date, byDay: Bool) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(parts.year ?? 0)-\(parts.month ?? 0)" + (byDay ? "-\(parts.day ?? 0)" : "")
        }
        func takeLegacy(_ original: Expense, _ date: Date, byDay: Bool) -> Bool {
            let wanted = period(date, byDay: byDay)
            guard let index = legacy.firstIndex(where: {
                $0.merchant == original.merchant && $0.amount == original.amount && period($0.date, byDay: byDay) == wanted
            }) else { return false }
            legacy.remove(at: index)
            return true
        }
        // Two originals nothing tells apart (made before the tie-break) are both kept, and log once.
        var seenIDs = Set<String>()
        for original in originals.sorted(by: { ($0.fixedID ?? "") < ($1.fixedID ?? "") }) {
            guard let id = original.fixedID else { continue }
            guard seenIDs.insert(id).inserted else {
                original.repeatsThrough = originals.first { $0.fixedID == id && $0 !== original }?.repeatsThrough
                    ?? original.repeatsThrough
                continue
            }
            let rule = original.rule
            let byDay = rule != .monthly
            let dates = RecurringSchedule.dates(rule: rule, anchor: original.date, day: original.repeatDay,
                                                after: original.repeatsThrough ?? original.date,
                                                through: now, calendar: calendar)
            for date in dates {
                guard !existing.contains(key(id, date)), !takeLegacy(original, date, byDay: byDay) else { continue }
                existing.insert(key(id, date))
                let copy = Expense(amount: original.amount, currencyMarker: original.currencyMarker,
                                   merchant: original.merchant, card: original.card,
                                   date: date, category: original.category)
                copy.isRepeat = true
                copy.fixedOf = id
                // Its own id: the same tie-break on every device (see above).
                copy.fixedID = UUID().uuidString
                copy.displayName = original.displayName
                copy.categorySource = original.categorySource
                // A fixed expense that doesn't count (paid by work) doesn't count every month.
                copy.countedAmount = original.countedAmount
                copy.uncountedReason = original.uncountedReason
                context.insert(copy)
                logged += 1
            }
            // Every date up to the last one is now logged or was already there.
            if let last = dates.last { original.repeatsThrough = last }
        }
        if logged > 0 || changed {
            do { try context.save() } catch { context.rollback(); throw error }
        }
        // Only once its first charge is saved does a plan leave the settings (2026-11-02, second
        // audit): before, a failed save lost the fixed expense for good.
        if !startedPlans.isEmpty {
            FixedPlan.save(FixedPlan.saved.filter { !startedPlans.contains($0.id) })
        }
        return logged
    }

    /// Two originals with one `fixedID`: the one `FixedTwins` picks stays, with the furthest
    /// `repeatsThrough` of both, and the other goes. When nothing tells them apart, both stay
    /// (deleting either could, on another device, delete the other one too). Returns the gone.
    private static func resolveTwins(_ originals: [Expense], in context: ModelContext) -> Set<ObjectIdentifier> {
        var gone = Set<ObjectIdentifier>()
        let groups = Dictionary(grouping: originals.filter { $0.fixedID != nil }, by: { $0.fixedID ?? "" })
        for twins in groups.values where twins.count > 1 {
            guard let keep = FixedTwins.keeper(twins.map(twinKey)) else { continue }
            let furthest = twins.compactMap(\.repeatsThrough).max()
            for (index, twin) in twins.enumerated() where index != keep {
                context.delete(twin)
                gone.insert(ObjectIdentifier(twin))
            }
            if let furthest { twins[keep].repeatsThrough = furthest }
        }
        return gone
    }

    /// What tells two originals apart on every device: what travels with them, never the
    /// store's own id. Fields people rarely edit, so a change not yet synced doesn't flip it.
    private static func twinKey(_ expense: Expense) -> FixedTwins.Key {
        let content = [BackupNumber.text(expense.amount), expense.currencyMarker ?? "", expense.merchant,
                       expense.rawAmount ?? "", expense.card ?? ""].joined(separator: "|")
        return FixedTwins.Key(date: expense.date, notice: expense.rawNotice, content: content)
    }

    /// The fixed expenses set up to start on a day that has now come: their first charge is
    /// logged, and from then on they repeat like any other. Returns how many started and the
    /// plans done, to take out of the settings once saved.
    private static func start(dueBy now: Date, in context: ModelContext,
                              calendar: Calendar) throws -> (started: Int, done: Set<UUID>) {
        let due = FixedPlan.saved.filter { $0.firstDate <= now }
        guard !due.isEmpty else { return (0, []) }
        var started = 0
        for plan in due {
            // Another phone may have started it already, and iCloud brought it here: by the
            // plan's id, or (started before ids) by merchant and first date.
            let id: String? = plan.id.uuidString
            let merchant = plan.merchant, first = plan.firstDate
            var byID = FetchDescriptor<Expense>(predicate: #Predicate { $0.repeatsMonthly == true && $0.fixedID == id })
            byID.fetchLimit = 1
            var byDate = FetchDescriptor<Expense>(predicate: #Predicate {
                $0.repeatsMonthly == true && $0.merchant == merchant && $0.date == first
            })
            byDate.fetchLimit = 1
            guard try context.fetch(byID).isEmpty, try context.fetch(byDate).isEmpty else { continue }
            context.insert(original(from: plan, calendar: calendar))
            started += 1
        }
        return (started, Set(due.map(\.id)))
    }

    /// A copy's original and day. Whole seconds: an original started from a plan carries a
    /// fraction of a millisecond of its own (`original(from:)`), and its copies with it.
    private static func key(_ id: String, _ date: Date) -> String {
        "\(id)|\(Int(date.timeIntervalSinceReferenceDate.rounded(.down)))"
    }

    /// Up to half a millisecond added to a plan's first date: two devices starting the same plan
    /// make originals that can be told apart, so both keep the same one (`FixedTwins`).
    static let tieBreakRange: ClosedRange<Double> = 0.000_001...0.000_5

    /// The first charge of a fixed expense, which every later copy repeats.
    static func original(from plan: FixedPlan, calendar: Calendar = .current) -> Expense {
        let date = plan.firstDate.addingTimeInterval(Double.random(in: tieBreakRange))
        let expense = Expense(amount: plan.value, currencyMarker: plan.currency, merchant: plan.merchant,
                              card: plan.card, date: date, category: plan.category)
        expense.repeatsMonthly = true
        // The plan's id: two devices starting the same plan make one fixed expense, not two.
        expense.fixedID = plan.id.uuidString
        // Its own date, fraction included: a weekly rule would otherwise repeat it the same day.
        expense.repeatsThrough = date
        expense.repeatRule = plan.rule
        if plan.repeatRule.kind == .months {
            // The day asked for («31»), not the first date's, which a short month cut back.
            expense.repeatDay = plan.day ?? calendar.component(.day, from: plan.firstDate)
        }
        return expense
    }

    // MARK: Changing one by hand

    /// Where a fixed expense saved in the sheet repeats from (2026-11-02, second audit).
    ///
    /// Just marked: from the last charge that already came, so months already lived (maybe
    /// logged by hand) aren't backfilled and this month's still to come is logged (Netflix of
    /// Oct 25 marked on Nov 10: Nov 25 comes; it skipped it when it started from Nov 10).
    /// Already repeating: never before its own date, so moving the date doesn't log a copy on
    /// the same day as the original.
    static func repeatsThrough(for date: Date, rule: RepeatRule, day: Int?, wasRepeating: Bool,
                               current: Date?, now: Date = .now, calendar: Calendar = .current) -> Date {
        guard wasRepeating else {
            return RecurringSchedule.lastCharge(rule: rule, anchor: date, day: day, through: now, calendar: calendar)
        }
        return max(current ?? date, date)
    }

    // MARK: Stopping and finding the original

    /// «Dejar de repetir»: what's to come stops, and the original keeps counting as the fixed
    /// charge it was (2026-11-02, second audit: rent of $8,000 turned into everyday spending on
    /// the 10th and «Hoy puedes gastar» dropped by $5,333 at once). It becomes like one of its
    /// copies, of itself, so it logs nothing more.
    static func stopRepeating(_ original: Expense) {
        let id = original.fixedID ?? UUID().uuidString
        original.fixedID = id
        original.repeatsMonthly = nil
        original.repeatsThrough = nil
        original.repeatDay = nil
        original.repeatRule = nil
        original.isRepeat = true
        original.fixedOf = id
    }

    /// The fixed expense a copy came from: by its id first; by merchant and amount only for a
    /// copy from before ids (two fixed expenses with one name and amount are told apart).
    static func original(of copy: Expense, in context: ModelContext) -> Expense? {
        guard copy.isRepeat == true else { return nil }
        if let of = copy.fixedOf {
            let id: String? = of
            var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.repeatsMonthly == true && $0.fixedID == id })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first
        }
        let merchant = copy.merchant, amount = copy.amount
        let candidates = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate {
            $0.repeatsMonthly == true && $0.merchant == merchant
        }))
        return candidates?.first { $0.amount == amount }
    }
}
