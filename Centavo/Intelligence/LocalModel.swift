import CentavoCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device model of Apple Intelligence, for the few things that need to read language:
/// a merchant's name, a sentence said to Siri, an odd Wallet notice, a note's wording.
///
/// It runs on the iPhone, with no network. It is only there with iOS 26 or later, Apple
/// Intelligence on, and the model downloaded: anywhere else every call answers `nil` and the
/// app does what it always did. Whatever it answers is checked by `CentavoCore` before it
/// touches an expense; it never adds anything up.
enum LocalModel {
    static var isReady: Bool {
        #if DEBUG
        // The demo modes (UI tests, screenshots) must look the same on every machine.
        if DemoData.isRequested { return false }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return OnDevice.isReady }
        #endif
        return false
    }

    /// A readable name and one of `candidates` for a merchant, as the model sees them.
    static func readMerchant(_ merchant: String, readable: String?, candidates: [String],
                             examples: [(merchant: String, category: String)]) async -> MerchantReading? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return await OnDevice.readMerchant(merchant, readable: readable, candidates: candidates,
                                               examples: examples)
        }
        #endif
        return nil
    }

    /// The parts of an expense said in one sentence, each as the words that were said.
    static func readSentence(_ sentence: String) async -> SentenceReading? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return await OnDevice.readSentence(sentence) }
        #endif
        return nil
    }

    /// Merchant, card and amount of a Wallet notice the plain reader could not follow.
    static func readNotice(_ text: String) async -> NoticeReading? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return await OnDevice.readNotice(text) }
        #endif
        return nil
    }

    /// Which of `candidates` loose words mean («cafecitos» → «Café»), if any.
    static func category(for words: String, candidates: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return await OnDevice.category(for: words, candidates: candidates) }
        #endif
        return nil
    }

    /// A warmer wording of a note, with the same figures (checked by `FactCheck`).
    static func reword(_ fact: SpendingFact) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return await OnDevice.reword(fact) }
        #endif
        return nil
    }
}

struct MerchantReading: Equatable, Sendable {
    var name: String?
    var category: String?
}

struct SentenceReading: Equatable, Sendable {
    var amount: String?
    var merchant: String?
    var when: String?
    var payment: String?
}

struct NoticeReading: Equatable, Sendable {
    var merchant: String?
    var card: String?
    var amount: String?
}

#if canImport(FoundationModels)
@available(iOS 26, *)
private enum OnDevice {
    static var isReady: Bool {
        let model = SystemLanguageModel.default
        return model.isAvailable && model.supportsLocale()
    }

    /// Apple's own phrase for the locale (it comes from the model's training), then the job.
    static func makeSession(_ job: String) -> LanguageModelSession {
        let text = "The person's locale is es_MX. You MUST answer in Mexican Spanish.\n" + job
        return LanguageModelSession(model: SystemLanguageModel.default, instructions: { text })
    }

    /// The same question gets the same answer.
    static let steady = GenerationOptions(sampling: .greedy, temperature: nil, maximumResponseTokens: nil)

    static func readMerchant(_ merchant: String, readable: String?, candidates: [String],
                             examples: [(merchant: String, category: String)]) async -> MerchantReading? {
        guard isReady, !candidates.isEmpty else { return nil }
        do {
            let name = DynamicGenerationSchema(type: String.self, guides: [])
            let category = DynamicGenerationSchema(type: String.self,
                                                   guides: [.anyOf(candidates + [CategoryPick.none])])
            let root = DynamicGenerationSchema(name: "Comercio", description: nil, properties: [
                .init(name: "nombre", description: "The shop's name as a person would write it",
                      schema: name, isOptional: false),
                .init(name: "categoria", description: "One of the person's categories, or Ninguna",
                      schema: category, isOptional: false),
            ])
            let schema = try GenerationSchema(root: root, dependencies: [])
            let session = makeSession("""
                You read the merchant names that card payments in Mexico arrive with.
                Write the shop's name the way a person would: proper capitals and accents, \
                abbreviations spelled out only when obvious. Never invent words or another shop.
                Then file it under one of the person's categories, following their own examples. \
                If the name does not say what was bought, answer Ninguna.
                """)
            let prompt = CategoryPick.prompt(merchant: merchant, readable: readable, examples: examples)
            let content = try await session.respond(to: prompt, schema: schema, options: steady).content
            return MerchantReading(name: try? content.value(String.self, forProperty: "nombre"),
                                   category: try? content.value(String.self, forProperty: "categoria"))
        } catch {
            // Guardrails, rate limits, the model still downloading: no reading, never an error.
            return nil
        }
    }

    static func readSentence(_ sentence: String) async -> SentenceReading? {
        guard isReady else { return nil }
        do {
            let session = makeSession("""
                Someone tells you an expense in one sentence. Copy each part with the exact words \
                they used. Never compute, convert or invent anything.
                """)
            let said = try await session.respond(to: sentence, generating: SaidExpense.self,
                                                 options: steady).content
            return SentenceReading(amount: said.monto, merchant: said.comercio, when: said.cuando,
                                   payment: said.pago)
        } catch {
            return nil
        }
    }

    static func readNotice(_ text: String) async -> NoticeReading? {
        guard isReady else { return nil }
        do {
            let session = makeSession("""
                You read a purchase notification from Apple Wallet. Copy the shop, the card and the \
                amount with its currency exactly as they appear. Never invent anything.
                """)
            let notice = try await session.respond(to: text, generating: WalletNoticeParts.self,
                                                   options: steady).content
            return NoticeReading(merchant: notice.comercio, card: notice.tarjeta, amount: notice.monto)
        } catch {
            return nil
        }
    }

    static func category(for words: String, candidates: [String]) async -> String? {
        guard isReady, !candidates.isEmpty else { return nil }
        do {
            let schema = GenerationSchema(type: String.self, description: nil,
                                          anyOf: candidates + [CategoryPick.none])
            let session = makeSession("""
                Pick the spending category these words refer to, from the list. \
                If none fits, answer Ninguna.
                """)
            let content = try await session.respond(to: words, schema: schema, options: steady).content
            return CategoryPick.validate(try content.value(String.self), among: candidates)
        } catch {
            return nil
        }
    }

    static func reword(_ fact: SpendingFact) async -> String? {
        guard isReady else { return nil }
        do {
            let session = makeSession("""
                Reword this note about someone's spending in one or two short sentences: warm, \
                plain, gender-neutral. Keep every figure exactly as it is and add no new ones. \
                No advice about debt, credit or investing.
                """)
            let note = try await session.respond(to: fact.line, generating: RewordedNote.self,
                                                 options: steady).content
            return note.texto
        } catch {
            return nil
        }
    }
}

@available(iOS 26, *)
@Generable
private struct SaidExpense {
    @Guide(description: "The amount exactly as said, with its currency word if there is one, e.g. 230 or 20 dólares")
    var monto: String
    @Guide(description: "The shop or what was bought, as said, without the amount, the day or how it was paid")
    var comercio: String
    @Guide(description: "The words that say when, e.g. ayer, el viernes, el 3. Empty if it doesn't say")
    var cuando: String
    @Guide(description: "The words that say how it was paid, e.g. en efectivo, con la Nu. Empty if it doesn't say")
    var pago: String
}

@available(iOS 26, *)
@Generable
private struct WalletNoticeParts {
    @Guide(description: "The shop, exactly as written")
    var comercio: String
    @Guide(description: "The card or bank, exactly as written. Empty if there is none")
    var tarjeta: String
    @Guide(description: "The amount with its currency, exactly as written, e.g. MXN 245.00")
    var monto: String
}

@available(iOS 26, *)
@Generable
private struct RewordedNote {
    @Guide(description: "The note, reworded, at most 160 characters")
    var texto: String
}
#endif
