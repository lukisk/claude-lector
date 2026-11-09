import Foundation

public enum IssueCategory: String, Codable, Sendable, CaseIterable {
    case grammar, typo, natural
}

public struct Issue: Codable, Sendable, Equatable {
    public var original: String
    public var replacement: String
    public var category: IssueCategory
    public var explanation: String

    public init(original: String, replacement: String, category: IssueCategory, explanation: String) {
        self.original = original
        self.replacement = replacement
        self.category = category
        self.explanation = explanation
    }
}

public struct CheckResult: Sendable {
    public var correctedText: String
    public var issues: [Issue]

    public init(correctedText: String, issues: [Issue]) {
        self.correctedText = correctedText
        self.issues = issues
    }
}

public enum EngineAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)
}

public enum EngineError: Error, Sendable, Equatable {
    /// The model declined (guardrails, unsupported language). Retrying won't help.
    case refused
    /// Engine-wide hiccup (5xx, rate limit, CLI crash/timeout). Stop for now, retry later; no attempt counted.
    case transient(String)
    /// The engine can't run (bad config, auth, unknown model, offline, missing CLI). Shown as ⚠︎; prompts wait.
    case unavailable(String)
    /// This prompt got a reply we couldn't use. Counts as an attempt for this prompt only.
    case badReply(String)
}

public protocol GrammarEngine: Sendable {
    var availability: EngineAvailability { get }
    func check(_ text: String) async throws(EngineError) -> CheckResult
}
