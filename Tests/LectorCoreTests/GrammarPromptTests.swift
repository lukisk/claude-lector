import Testing
@testable import LectorCore

private let json = #"{"correctedText":"I went home.","issues":[{"original":"I go","replacement":"I went","category":"grammar","explanation":"Use past tense for yesterday."}]}"#

@Test func parsesPlainJSON() throws {
    let r = try GrammarPrompt.parse(json)
    #expect(r.correctedText == "I went home.")
    #expect(r.issues == [LectorCore.Issue(original: "I go", replacement: "I went", category: .grammar, explanation: "Use past tense for yesterday.")])
}

@Test func parsesFencedJSONWithProse() throws {
    let r = try GrammarPrompt.parse("Here you go:\n```json\n\(json)\n```\nHope it helps.")
    #expect(r.issues.count == 1)
}

@Test func dropsUnknownCategory() throws {
    let r = try GrammarPrompt.parse(#"{"correctedText":"x","issues":[{"original":"a","replacement":"b","category":"style","explanation":"e"}]}"#)
    #expect(r.issues.isEmpty)
}

@Test func garbageThrowsBadReply() {
    do { _ = try GrammarPrompt.parse("sorry, I can't"); Issue.record("expected throw") }
    catch { if case .badReply = error {} else { Issue.record("got \(error)") } }
}
