import Foundation

/// One thing the app remembers about a merchant, as «Lo que recuerdo» lists it: what arrives
/// as `sent` is written down as `name`, under `category` (owner's request, 2026-11-11).
///
/// It is not stored: it is read from the two lists that already sync with the settings, the
/// names (`MerchantRenames`) and the categories (`CategoryRules`).
public struct MerchantRule: Equatable, Identifiable, Sendable {
    /// The text it arrives as, as `MerchantKey` compares it.
    public var sent: String
    /// The name it is saved with; `nil`: the one it arrives with.
    public var name: String?
    /// The category it gets; `nil`: none was chosen, or (`goesUncategorized`) none on purpose.
    public var category: String?
    /// The owner decided it goes without a category: nothing is filled in for it.
    public var goesUncategorized: Bool

    /// The text as someone wrote it, when that is known (accents are not part of `sent`).
    public var written: String?

    public var id: String { sent }

    /// The text it arrives as, for a screen: as it was written or, failing that, in capitals,
    /// the way a bank usually sends it.
    public var arrivesAs: String { written ?? sent.uppercased() }

    /// What was chosen for its category, or `nil` if nobody chose.
    public var choice: CategoryRules.Choice? {
        category.map(CategoryRules.Choice.category) ?? (goesUncategorized ? .uncategorized : nil)
    }

    public init(sent: String, name: String? = nil, category: String? = nil, goesUncategorized: Bool = false,
                written: String? = nil) {
        self.written = written
        self.sent = sent
        self.name = name
        self.category = category
        self.goesUncategorized = goesUncategorized
    }
}

/// Which rule applies to which text, and how the rules change. Pure: the app hands over the
/// two stored lists and saves what comes back.
public enum MerchantRules {
    /// What a payment that arrives as `sent` is saved with.
    public struct Applied: Equatable, Sendable {
        /// The owner's name for it, or `nil` to keep the one it came with.
        public var name: String?
        /// The owner's last choice of category for it, or `nil` if they never chose.
        public var choice: CategoryRules.Choice?
    }

    /// The rule for a payment that arrives as `sent`. Case, accents and spaces don't count;
    /// anything else does: «OXXO 1234» and «OXXO 5678» are two places (decision 2026-10-11).
    /// The category is the one chosen for the name it ends up with.
    public static func applied(to sent: String, renames: MerchantRenames,
                               categories: CategoryRules) -> Applied {
        let name = renames.name(for: sent)
        return Applied(name: name, choice: categories.choice(for: name ?? sent))
    }

    /// Every rule, for the list: the merchants with a name of the owner's first, then the ones
    /// with only a category; in each group, the newest first.
    public static func list(renames: MerchantRenames, categories: CategoryRules) -> [MerchantRule] {
        var rules: [MerchantRule] = []
        // A category kept under a name some rule gives, or under a text that is renamed on
        // arrival, is part of that rule, not one of its own.
        var covered = Set<String>()
        for entry in renames.entries.reversed() {
            let choice = categories.choice(for: entry.to)
            var rule = rule(sent: entry.from, name: entry.to, choice: choice)
            rule.written = entry.written
            rules.append(rule)
            covered.insert(entry.from)
            covered.insert(MerchantKey.normalized(entry.to))
        }
        for entry in categories.entries.reversed() where !covered.contains(entry.merchant) {
            var rule = rule(sent: entry.merchant, name: nil,
                            choice: entry.category.map(CategoryRules.Choice.category) ?? .uncategorized)
            rule.written = entry.written
            rules.append(rule)
        }
        return rules
    }

    private static func rule(sent: String, name: String?, choice: CategoryRules.Choice?) -> MerchantRule {
        switch choice {
        case .category(let category): MerchantRule(sent: sent, name: name, category: category)
        case .uncategorized: MerchantRule(sent: sent, name: name, goesUncategorized: true)
        case nil: MerchantRule(sent: sent, name: name)
        }
    }

    /// Every text that means the merchant now called `merchant`: itself, and what arrives
    /// under other texts and is renamed to it. As `MerchantKey` compares them.
    public static func texts(for merchant: String, renames: MerchantRenames) -> [String] {
        guard let key = MerchantKey.memory(merchant) else { return [] }
        return [key] + renames.entries.filter { MerchantKey.normalized($0.to) == key && $0.from != key }.map(\.from)
    }

    /// The expense sheet saved a correction: what was `sent` is now `name`, with `category`
    /// showing (`nil` or blank: none).
    ///
    /// - A new name is remembered for what arrives as `sent`.
    /// - A category picked in this correction (`choseCategory`, taking it off included) is the
    ///   choice for `name`: the last one wins.
    /// - Renamed with the category left as it was: that category goes with the new name, if
    ///   someone chose it (`categoryIsTheirs`; a suggestion nobody confirmed is not a choice).
    ///   Failing that, whatever was chosen for the old text follows, so a category never
    ///   depends on the history once the name changes.
    public static func learn(sent: String, name: String, category: String?, choseCategory: Bool,
                             categoryIsTheirs: Bool = true,
                             renames: inout MerchantRenames, categories: inout CategoryRules) {
        let clean = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let renamed = MerchantKey.memory(sent) != MerchantKey.memory(name)
        let before = categories.choice(for: sent)
        // `sent` may itself be a name the owner gave (the payment arrived already renamed):
        // then the texts behind it move on to the new name and the old one is nobody's.
        let wasTheirName = renamed && isNamed(sent, in: renames)
        if renamed { renames.rename(sent, to: name) }
        if wasTheirName { renames.forget(sent) }
        if choseCategory {
            categories.learn(clean, for: name)
        } else if renamed {
            if !clean.isEmpty, categoryIsTheirs {
                categories.learn(clean, for: name)
            } else if categories.choice(for: name) == nil, let before {
                categories.learn(before.category, for: name)
            }
        }
        if wasTheirName { categories.forget(sent) }
    }

    /// «Lo que recuerdo» changed `rule`: from now on it is saved as `name` (blank, or the text
    /// it arrives as: with the name it comes with) and filed as `choice` says (`nil`: nobody
    /// chooses, so the history and the catalog decide as for any other merchant).
    public static func change(_ rule: MerchantRule, name: String, choice: CategoryRules.Choice?,
                              renames: inout MerchantRenames, categories: inout CategoryRules) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldHolder = rule.name ?? rule.sent
        let holder: String
        if let target = MerchantKey.memory(clean), target != rule.sent {
            // As it reads on screen, so the text keeps its accents and capitals.
            renames.rename(rule.arrivesAs, to: clean)
            holder = clean
        } else {
            renames.forget(rule.sent)
            // As it reads on screen, so the choice keeps its accents and capitals.
            holder = rule.arrivesAs
        }
        if let choice {
            categories.learn(choice.category, for: holder)
        } else {
            categories.forget(holder)
        }
        // The category kept under the old name goes with it, unless another rule still uses it.
        if MerchantKey.normalized(oldHolder) != MerchantKey.normalized(holder), !isNamed(oldHolder, in: renames) {
            categories.forget(oldHolder)
        }
    }

    /// The rule is gone: what arrives as `rule.sent` keeps the name it comes with, and its
    /// category is decided as for any merchant nobody chose for. Expenses are not touched.
    public static func remove(_ rule: MerchantRule, renames: inout MerchantRenames,
                              categories: inout CategoryRules) {
        renames.forget(rule.sent)
        categories.forget(rule.sent)
        if let name = rule.name, !isNamed(name, in: renames) { categories.forget(name) }
    }

    /// Whether some text is still renamed to `name`.
    private static func isNamed(_ name: String, in renames: MerchantRenames) -> Bool {
        let key = MerchantKey.normalized(name)
        return renames.entries.contains { MerchantKey.normalized($0.to) == key }
    }
}

extension CategoryRules.Choice {
    /// The category chosen, or `nil` for «none, on purpose».
    public var category: String? {
        if case .category(let name) = self { return name }
        return nil
    }
}

/// Applying a rule to what was written down before it existed: which saved expenses change, and
/// to what. Only when the owner asks for it, and never over something they set by hand.
public struct MerchantBackfill: Equatable, Sendable {
    /// What changes in one expense.
    public struct Change: Equatable, Sendable {
        /// The name it takes, or `nil` to keep its own.
        public var name: String?
        /// The category it takes, or `nil` to keep its own.
        public var category: String?
    }

    private let texts: Set<String>
    private let name: String?
    private let category: String?
    private let previous: String?

    /// - `texts`: the merchant's texts (`MerchantRules.texts`); an expense under any other
    ///   name is someone else, or one renamed by hand, and is left alone.
    /// - `name`: the name the rule gives, or `nil` to leave names as they are.
    /// - `category`: the category the rule gives; `nil` or blank leaves categories as they are
    ///   (a category is never taken off expenses already saved).
    /// - `previous`: the category the rule gave until now. Only an expense with that one, with
    ///   none, or with a suggestion nobody confirmed takes the new one: any other was put there
    ///   by hand.
    public init(texts: [String], name: String?, category: String?, replacing previous: String?) {
        self.texts = Set(texts.map(MerchantKey.normalized))
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = cleanName.isEmpty ? nil : cleanName
        let cleanCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.category = cleanCategory.isEmpty ? nil : cleanCategory
        self.previous = previous.map(CategoryMemory.fold)
    }

    /// What changes in an expense saved as `merchant` under `category`, or `nil` if nothing does.
    public func change(merchant: String, category current: String?, isSuggested: Bool) -> Change? {
        guard let key = MerchantKey.memory(merchant), texts.contains(key) else { return nil }
        var change = Change()
        if let name, merchant != name { change.name = name }
        if let category {
            let has = CategoryMemory.fold(current ?? "")
            let replaceable = has.isEmpty || isSuggested || has == previous
            if replaceable, has != CategoryMemory.fold(category) || isSuggested { change.category = category }
        }
        return change.name == nil && change.category == nil ? nil : change
    }
}
