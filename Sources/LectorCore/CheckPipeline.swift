import Foundation

public enum CheckOutcome: Sendable, Equatable {
    case skipped(SkipReason)
    /// `text` is the checked prose (chunks joined by a blank line); issue offsets refer to it.
    case checked(text: String, issues: [LocatedIssue], truncated: Bool)
    case refused
}

/// One inbox record → one outcome. Throws `EngineError.transient` / `.unavailable`
/// so the caller can keep the prompt queued and retry later.
public struct CheckPipeline: Sendable {
    let engine: any GrammarEngine

    public init(engine: any GrammarEngine) {
        self.engine = engine
    }

    public func run(_ record: InboxRecord) async throws(EngineError) -> CheckOutcome {
        guard record.isInteractive else { return .skipped(.nonInteractive) }
        let prepared: PreparedPrompt
        switch PromptFilter.prepare(record.prompt) {
        case .failure(let reason): return .skipped(reason)
        case .success(let p): prepared = p
        }

        var all: [LocatedIssue] = []
        var shift = 0
        var hasNatural = false
        for chunk in prepared.chunks {
            let result: CheckResult
            do { result = try await engine.check(chunk) }
            catch .refused { return .refused }
            for var li in IssueLocator.locate(result.issues, in: chunk) {
                if li.issue.category == .natural {
                    if hasNatural { continue }
                    hasNatural = true
                }
                li.offset += shift
                all.append(li)
            }
            shift += chunk.count + 2
        }
        return .checked(text: prepared.chunks.joined(separator: "\n\n"), issues: all, truncated: prepared.truncated)
    }
}
