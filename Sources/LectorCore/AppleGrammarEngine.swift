import Foundation
import FoundationModels

@Generable
struct GrammarReport {
    @Guide(description: "The full input text with every mistake fixed. Identical to the input if nothing is wrong.")
    var correctedText: String
    @Guide(description: "Mistakes found. Empty if the text is fine.")
    var issues: [GrammarIssue]
}

@Generable
struct GrammarIssue {
    @Guide(description: "The wrong words, copied exactly, character for character, from the input. Keep it short: just the wrong words plus at most two neighbours.")
    var original: String
    @Guide(description: "What the wrong words should be replaced with.")
    var replacement: String
    @Guide(description: "grammar = tense, article, preposition, word order, agreement; typo = misspelled word; natural = correct but a native speaker would phrase it differently", .anyOf(["grammar", "typo", "natural"]))
    var category: String
    @Guide(description: "One short, plain-English sentence explaining the rule.")
    var explanation: String
}

/// Grammar checking with Apple's on-device Foundation Models.
public final class AppleGrammarEngine: GrammarEngine {
    public static let instructions = GrammarPrompt.instructions

    public init() {}

    public var availability: EngineAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is turned off")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The model is still downloading")
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This Mac can't run Apple Intelligence")
        case .unavailable:
            return .unavailable(reason: "The model is unavailable")
        }
    }

    public func check(_ text: String) async throws(EngineError) -> CheckResult {
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: "Check this text:\n\n\(text)",
                generating: GrammarReport.self,
                options: GenerationOptions(samplingMode: .greedy)
            )
            let report = response.content
            let issues = report.issues.compactMap { i -> Issue? in
                guard let category = IssueCategory(rawValue: i.category) else { return nil }
                return Issue(original: i.original, replacement: i.replacement, category: category, explanation: i.explanation)
            }
            return CheckResult(correctedText: report.correctedText, issues: issues)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .unsupportedLanguageOrLocale:
                throw .refused
            default:
                throw .transient(String(describing: error))
            }
        } catch {
            throw .transient(String(describing: error))
        }
    }
}
