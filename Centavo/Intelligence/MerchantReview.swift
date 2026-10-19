import CentavoCore
import Foundation
import SwiftData

/// While the app is open, the on-device model gives the merchants that need it a readable
/// name and a suggested category, a few at a time. Never during a Wallet capture: that runs in
/// the background, where the model is rationed, and a payment must never wait for it.
@MainActor
enum MerchantReview {
    /// Merchants already looked at (folded names). On this phone only: another phone looks
    /// again, and finds what iCloud already brought.
    static let reviewedKey = "modeloComerciosRevisados"
    /// Enough to catch up on a few days of payments without keeping the model busy.
    static let perRun = 8

    /// One review at a time: the screen asks again whenever expenses come in.
    private static var isRunning = false

    static func run(in context: ModelContext) async {
        guard LocalModel.isReady, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let customCategories = UserCatalog.decode(
            UserDefaults.standard.string(forKey: UserCatalog.categoriesKey) ?? "").map(\.name)
        let descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let all = try? context.fetch(descriptor) else { return }
        var reviewed = Set(UserDefaults.standard.stringArray(forKey: reviewedKey) ?? [])
        let history = all.map(\.categorized)
        let candidates = CategoryPick.candidates(CategoryStyle.common.map(\.name), customCategories,
                                                 CategoryMemory.known(in: history))
        let examples = CategoryPick.examples(from: history)

        var groups: [String: [Expense]] = [:]
        var order: [String] = []
        for expense in all where expense.merchant != "Sin comercio" {
            let key = UserCatalog.fold(expense.merchant)
            guard !reviewed.contains(key) else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(expense)
        }

        var asked = 0
        for key in order where asked < perRun {
            guard let group = groups[key], let merchant = group.first?.merchant else { continue }
            // Names only for what Wallet sent and nobody renamed (a typed name is theirs, as
            // written), and never for a brand, which already reads as itself.
            let renamable = group.filter { $0.rawAmount != nil && $0.displayName != $0.merchant }
            let wantsName = !renamable.isEmpty && MerchantName.brand(for: merchant) == nil
            // Categories only where neither you nor the catalog has one, and nobody took it off.
            let open = group.filter { $0.category == nil && $0.categorySource != Expense.clearedCategory }
            let wantsCategory = !open.isEmpty && MerchantCatalog.suggestion(for: merchant, history: history) == nil
            // Nothing to ask is not «reviewed»: a later Wallet charge may need it.
            guard wantsName || wantsCategory else { continue }

            asked += 1
            let plain = MerchantName.readable(merchant)
            let reading = await LocalModel.readMerchant(merchant, readable: plain,
                                                        candidates: candidates, examples: examples)
            // The screen moved on (a payment came in, a delete) or the model went away (turned
            // off, still downloading): look again next time.
            if Task.isCancelled || !LocalModel.isReady { break }
            reviewed.insert(key)
            // No answer while the model is there (a guardrail): leave this one be.
            guard let reading else { continue }
            // Rows deleted while the model was thinking are gone; never write to them.
            let alive: (Expense) -> Bool = { !$0.isDeleted && $0.modelContext != nil }
            if wantsName, let name = reading.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               name != merchant, MerchantName.isFaithful(name, to: merchant) {
                for expense in renamable where alive(expense)
                    && (expense.displayName == nil || expense.displayName == plain) {
                    expense.displayName = name
                }
            }
            if wantsCategory, let category = CategoryPick.validate(reading.category, among: candidates) {
                for expense in open where alive(expense) && expense.category == nil {
                    expense.category = category
                    expense.categorySource = Expense.suggestedCategory
                }
            }
        }
        UserDefaults.standard.set(Array(reviewed), forKey: reviewedKey)
        try? context.save()
    }
}
