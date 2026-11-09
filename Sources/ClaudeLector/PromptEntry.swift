import Foundation
import LectorCore
import SwiftData

@Model
final class PromptEntry {
    @Attribute(.unique) var promptId: String
    var sessionId: String
    var cwd: String
    var projectName: String
    var prompt: String
    var timestamp: Date
    var entrypoint: String?
    var attended: String?
    var statusRaw: String
    var checkedText: String?
    var issuesJSON: Data?
    var truncated: Bool
    var skipReasonRaw: String?
    var attempts: Int
    var seen: Bool

    init(record: InboxRecord) {
        promptId = record.promptId
        sessionId = record.sessionId
        cwd = record.cwd
        projectName = record.projectName
        prompt = record.prompt
        timestamp = record.timestamp
        entrypoint = record.entrypoint
        attended = record.attended
        statusRaw = EntryStatus.pending.rawValue
        truncated = false
        attempts = 0
        seen = false
    }

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var issues: [LocatedIssue] {
        get { issuesJSON.flatMap { try? JSONDecoder().decode([LocatedIssue].self, from: $0) } ?? [] }
        set { issuesJSON = try? JSONEncoder().encode(newValue) }
    }

    var record: InboxRecord {
        InboxRecord(promptId: promptId, sessionId: sessionId, cwd: cwd, prompt: prompt,
                    timestamp: timestamp, entrypoint: entrypoint, attended: attended)
    }

    var summary: EntrySummary {
        EntrySummary(status: status, categories: Set(issues.map(\.issue.category)), seen: seen, isManual: record.isManual)
    }

    func apply(_ outcome: CheckOutcome) {
        switch outcome {
        case .skipped(let reason):
            status = .skipped
            skipReasonRaw = reason.rawValue
        case .refused:
            status = .refused
        case .checked(let text, let located, let wasTruncated):
            status = .checked
            checkedText = text
            issues = located
            truncated = wasTruncated
        }
    }
}
