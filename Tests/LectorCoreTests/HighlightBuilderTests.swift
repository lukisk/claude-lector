import Foundation
import Testing
@testable import LectorCore

private func located(_ o: String, _ r: String, at offset: Int, _ c: IssueCategory = .grammar) -> LocatedIssue {
    LocatedIssue(issue: issue(o, r, c), offset: offset, length: o.count)
}

private func highlighted(_ s: AttributedString) -> [(String, IssueCategory)] {
    s.runs.compactMap { run in run[IssueCategoryAttribute.self].map { (String(s[run.range].characters), $0) } }
}

@Test func originalHighlightsExactRun() {
    let t = "🚀 Lukáš said it are fine."
    let a = HighlightBuilder.original(t, issues: [located("it are", "it is", at: 13)])
    #expect(String(a.characters) == t)
    let h = highlighted(a)
    #expect(h.count == 1)
    #expect(h.first?.0 == "it are")
    #expect(h.first?.1 == .grammar)
}

@Test func correctedAppliesReplacements() {
    let t = "Yesterday I fix two bug."
    let issues = [located("fix", "fixed", at: 12), located("bug", "bugs", at: 20, .typo)]
    let a = HighlightBuilder.corrected(t, issues: issues)
    #expect(String(a.characters) == "Yesterday I fixed two bugs.")
    #expect(highlighted(a).map(\.0) == ["fixed", "bugs"])
    #expect(highlighted(a).map(\.1) == [.grammar, .typo])
}

@Test func noIssuesNoHighlights() {
    #expect(highlighted(HighlightBuilder.original("All good here.", issues: [])).isEmpty)
}
