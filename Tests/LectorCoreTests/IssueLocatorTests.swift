import Testing
@testable import LectorCore

func issue(_ original: String, _ replacement: String, _ category: IssueCategory = .grammar) -> LectorCore.Issue {
    LectorCore.Issue(original: original, replacement: replacement, category: category, explanation: "x")
}

@Test func dropsIssueNotInText() {
    #expect(IssueLocator.locate([issue("teh", "the")], in: "I fixed the bug.").isEmpty)
}

@Test func dropsNoOpReplacement() {
    #expect(IssueLocator.locate([issue("bug", "Bug ")], in: "I fixed the bug.").isEmpty)
}

@Test func locatesInOrderOnRepeats() {
    let t = "I want to to go and I want to to stay."
    let r = IssueLocator.locate([issue("to to", "to"), issue("to to", "to")], in: t)
    #expect(r.map(\.offset) == [7, 27])
    #expect(r.map(\.length) == [5, 5])
}

@Test func offsetsAreCharactersNotUTF16() {
    let t = "🚀 Lukáš said it are fine."
    let r = IssueLocator.locate([issue("it are", "it is")], in: t)
    #expect(r.first?.offset == 13)
    #expect(r.first?.length == 6)
}

@Test func keepsOnlyFirstNatural() {
    let t = "I want make a test and do a review."
    let r = IssueLocator.locate([issue("want make", "want to make", .natural), issue("do a review", "review it", .natural)], in: t)
    #expect(r.count == 1)
    #expect(r.first?.issue.original == "want make")
}

@Test func dropsOverlapping() {
    let t = "He go to school yesterday."
    let r = IssueLocator.locate([issue("He go", "He went"), issue("go to", "went to")], in: t)
    #expect(r.map(\.issue.original) == ["He go"])
}

@Test func findsEarlierOccurrenceWhenModelOrderIsReversed() {
    let t = "I has a dog and it eat bones."
    let r = IssueLocator.locate([issue("it eat", "it eats"), issue("I has", "I have")], in: t)
    #expect(Set(r.map(\.offset)) == [0, 16])
}

@Test func doesNotMatchInsideWords() {
    let t = "I have a apple and a orange."
    let r = IssueLocator.locate([issue("a", "an"), issue("a", "an")], in: t)
    #expect(r.map(\.offset) == [7, 19])
    #expect(String(HighlightBuilder.corrected(t, issues: r).characters) == "I have an apple and an orange.")
}

@Test func prepositionNotMatchedInsideEarlierWord() {
    let t = "I am thinking in the morning"
    let r = IssueLocator.locate([issue("in", "on")], in: t)
    #expect(r.map(\.offset) == [14])
}

@Test func punctuationEdgedOriginalStillMatches() {
    let t = "Is it ok ?"
    #expect(IssueLocator.locate([issue("ok ?", "ok?", .typo)], in: t).map(\.offset) == [6])
}
