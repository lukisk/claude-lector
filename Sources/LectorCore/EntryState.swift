import Foundation

public enum EntryStatus: String, Codable, Sendable {
    case pending, checked, skipped, refused
    /// Gave up after repeated unusable replies; shown in the list so nothing disappears silently.
    case failed
}

public struct EntrySummary: Sendable {
    public var status: EntryStatus
    public var categories: Set<IssueCategory>
    public var seen: Bool

    public init(status: EntryStatus, categories: Set<IssueCategory>, seen: Bool) {
        self.status = status
        self.categories = categories
        self.seen = seen
    }
}

/// Pure rules for the menu bar badge and retries, kept out of the app target so they're testable.
public enum EntryState {
    public static let maxAttempts = 3

    /// Unseen, checked prompts with at least one grammar mistake.
    public static func badgeCount(_ entries: [EntrySummary]) -> Int {
        entries.filter { $0.status == .checked && !$0.seen && $0.categories.contains(.grammar) }.count
    }

    public enum Reaction: Equatable, Sendable {
        /// Stop processing the queue for now; `unavailable` carries the reason to show (⚠︎), if any.
        case stopPass(unavailable: String?)
        case setStatus(EntryStatus, countAttempt: Bool)
    }

    /// What to do when checking one entry failed. Only per-entry failures cost attempts,
    /// so an outage never burns through the queue.
    public static func reaction(to error: EngineError, attempts: Int) -> Reaction {
        switch error {
        case .refused: .setStatus(.refused, countAttempt: false)
        case .transient: .stopPass(unavailable: nil)
        case .unavailable(let reason): .stopPass(unavailable: reason)
        case .badReply: .setStatus(attempts + 1 >= maxAttempts ? .failed : .pending, countAttempt: true)
        }
    }
}
