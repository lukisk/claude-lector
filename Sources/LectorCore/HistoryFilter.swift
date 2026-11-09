import Foundation

/// What the history window needs to know about an entry to filter and label it.
public struct HistoryItem: Sendable {
    public var status: EntryStatus
    public var categories: [IssueCategory]
    public var text: String
    public var project: String

    public init(status: EntryStatus, categories: some Sequence<IssueCategory>, text: String, project: String) {
        self.status = status
        self.categories = Array(categories)
        self.text = text
        self.project = project
    }

    /// "2 grammar · 1 typo · 1 tip"
    public static func issueSummary(_ categories: [IssueCategory]) -> String {
        let labels: [(IssueCategory, String)] = [(.grammar, "grammar"), (.typo, "typo"), (.natural, "tip")]
        return labels.compactMap { category, label in
            let n = categories.filter { $0 == category }.count
            return n == 0 ? nil : "\(n) \(label)"
        }.joined(separator: " · ")
    }
}

public enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, withMistakes, grammarOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .withMistakes: "With mistakes"
        case .grammarOnly: "Grammar only"
        }
    }

    public func matches(_ item: HistoryItem, query: String = "") -> Bool {
        guard item.status == .checked || item.status == .failed else { return false }
        switch self {
        case .all: break
        case .withMistakes: if item.categories.isEmpty { return false }
        case .grammarOnly: if !item.categories.contains(.grammar) { return false }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return item.text.localizedCaseInsensitiveContains(q) || item.project.localizedCaseInsensitiveContains(q)
    }
}
