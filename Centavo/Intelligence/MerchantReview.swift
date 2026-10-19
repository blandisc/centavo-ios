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

        for key in order.prefix(perRun) {
            guard let group = groups[key], let merchant = group.first?.merchant else { continue }
            // Names only for what Wallet sent: a name someone typed is theirs, as they wrote it.
            let fromWallet = group.contains { $0.rawAmount != nil }
            // Categories only where neither you nor the catalog has one.
            let needsCategory = group.contains { $0.category == nil }
                && MerchantCatalog.suggestion(for: merchant, history: history) == nil
            reviewed.insert(key)
            guard fromWallet || needsCategory else { continue }

            let plain = MerchantName.readable(merchant)
            guard let reading = await LocalModel.readMerchant(merchant, readable: plain,
                                                              candidates: candidates, examples: examples)
            else {
                // The model went away (turned off, still downloading): look again next time.
                // While it is there, no answer for this name (a guardrail) means leave it be.
                if !LocalModel.isReady { reviewed.remove(key); break }
                continue
            }
            if fromWallet, let name = reading.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               name != merchant, MerchantName.isFaithful(name, to: merchant) {
                for expense in group where expense.rawAmount != nil
                    && (expense.displayName == nil || expense.displayName == plain) {
                    expense.displayName = name
                }
            }
            if needsCategory, let category = CategoryPick.validate(reading.category, among: candidates) {
                for expense in group where expense.category == nil {
                    expense.category = category
                    expense.categorySource = Expense.suggestedCategory
                }
            }
        }
        UserDefaults.standard.set(Array(reviewed), forKey: reviewedKey)
        try? context.save()
    }
}
