import Testing
@testable import LectorCore

private let modelAvailable = AppleGrammarEngine().availability == .available

@Test(.enabled(if: modelAvailable))
func findsObviousError() async throws {
    let t = "Yesterday I go to the office and fix two bug."
    let r = try await AppleGrammarEngine().check(t)
    #expect(!IssueLocator.locate(r.issues, in: t).isEmpty)
}

@Test(.enabled(if: modelAvailable))
func leavesCorrectTextAlone() async throws {
    let t = "Please rename the function and update the tests."
    let located = IssueLocator.locate(try await AppleGrammarEngine().check(t).issues, in: t)
    #expect(located.filter { $0.issue.category == .grammar }.isEmpty)
}
