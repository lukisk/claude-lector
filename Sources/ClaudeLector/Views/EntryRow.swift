import LectorCore
import SwiftUI

struct EntryRow: View {
    let entry: PromptEntry
    let isNew: Bool

    var body: some View {
        let text = entry.checkedText ?? entry.prompt
        let issues = entry.issues
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isNew { Circle().fill(.blue).frame(width: 6, height: 6) }
                Text(entry.projectName).font(.caption.weight(.medium))
                Text(entry.timestamp, format: .relative(presentation: .named)).font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.status == .failed {
                    Label("couldn't check", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                } else if issues.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

            Text(Self.styled(HighlightBuilder.original(text, issues: issues), strike: true))
                .textSelection(.enabled)

            if !issues.isEmpty {
                Text(Self.styled(HighlightBuilder.corrected(text, issues: issues), strike: false))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, li in
                        IssueLine(issue: li.issue)
                    }
                }
            }

            if entry.truncated {
                Text("checked first 3000 chars").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    static func color(_ c: IssueCategory) -> Color {
        switch c {
        case .grammar: .red
        case .typo: .orange
        case .natural: .blue
        }
    }

    /// Turns category-tagged runs into visible styling. Typos are muted.
    static func styled(_ source: AttributedString, strike: Bool) -> AttributedString {
        var out = source
        for run in source.runs {
            guard let category = run[IssueCategoryAttribute.self] else { continue }
            let c = color(category)
            out[run.range].backgroundColor = c.opacity(category == .typo ? 0.12 : 0.22)
            out[run.range].underlineStyle = .single
            out[run.range].underlineColor = NSColor(c)
            if strike && category == .typo { out[run.range].foregroundColor = .secondary }
        }
        return out
    }
}

struct IssueLine: View {
    let issue: LectorCore.Issue

    private var line: AttributedString {
        var original = AttributedString(issue.original)
        original.strikethroughStyle = .single
        var replacement = AttributedString(issue.replacement)
        replacement.inlinePresentationIntent = .stronglyEmphasized
        var explanation = AttributedString(" — \(issue.explanation)")
        explanation.foregroundColor = .secondary
        return original + AttributedString(" → ") + replacement + explanation
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(EntryRow.color(issue.category).opacity(issue.category == .typo ? 0.6 : 1)).frame(width: 7, height: 7)
            Text(line).font(.callout)
                .textSelection(.enabled)
        }
        .opacity(issue.category == .typo ? 0.75 : 1)
    }
}
