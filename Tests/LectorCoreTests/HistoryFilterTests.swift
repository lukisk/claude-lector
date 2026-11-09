import Testing
@testable import LectorCore

private func item(_ categories: Set<IssueCategory>, text: String = "I go home", project: String = "my-app", status: EntryStatus = .checked) -> HistoryItem {
    HistoryItem(status: status, categories: categories, text: text, project: project)
}

@Test func allShowsCheckedAndFailed() {
    #expect(HistoryFilter.all.matches(item([])))
    #expect(HistoryFilter.all.matches(item([], status: .failed)))
    #expect(!HistoryFilter.all.matches(item([], status: .pending)))
    #expect(!HistoryFilter.all.matches(item([], status: .skipped)))
}

@Test func withMistakesNeedsAnyIssue() {
    #expect(HistoryFilter.withMistakes.matches(item([.typo])))
    #expect(HistoryFilter.withMistakes.matches(item([.natural])))
    #expect(!HistoryFilter.withMistakes.matches(item([])))
}

@Test func grammarOnlyNeedsGrammar() {
    #expect(HistoryFilter.grammarOnly.matches(item([.grammar, .typo])))
    #expect(!HistoryFilter.grammarOnly.matches(item([.typo, .natural])))
}

@Test func searchMatchesTextAndProjectCaseInsensitively() {
    #expect(HistoryFilter.all.matches(item([], text: "Please rename the Function"), query: "function"))
    #expect(HistoryFilter.all.matches(item([], project: "claude-lector"), query: "LECTOR"))
    #expect(!HistoryFilter.all.matches(item([], text: "hello there"), query: "deploy"))
    #expect(HistoryFilter.all.matches(item([]), query: "   "))
}

@Test func issueSummaryCountsByCategory() {
    #expect(HistoryItem.issueSummary([.grammar, .grammar, .typo]) == "2 grammar · 1 typo")
    #expect(HistoryItem.issueSummary([.natural]) == "1 tip")
    #expect(HistoryItem.issueSummary([]) == "")
}
