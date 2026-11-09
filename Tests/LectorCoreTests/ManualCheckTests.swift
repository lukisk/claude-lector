import Foundation
import Testing
@testable import LectorCore

@Test func manualShortTextIsChecked() throws {
    let r = try PromptFilter.prepare("I has a idea", mode: .manual).get()
    #expect(r.chunks == ["I has a idea"])
}

@Test func manualTwoWordsAreChecked() throws {
    #expect(try PromptFilter.prepare("teh cat", mode: .manual).get().chunks == ["teh cat"])
}

@Test func manualLeadingPathIsNotASlashCommand() throws {
    let text = try PromptFilter.prepare("/tmp is full of junk files again", mode: .manual).get().chunks.joined()
    #expect(text.contains("is full of junk files"))
}

@Test func manualSlovakIsStillNotEnglish() {
    #expect(PromptFilter.prepare("chcel by som vediet preco to nefunguje", mode: .manual) == .failure(.notEnglish))
}

@Test func manualEmptyIsTooShort() {
    #expect(PromptFilter.prepare("   \n ", mode: .manual) == .failure(.tooShort))
}

@Test func automaticModeUnchanged() {
    #expect(PromptFilter.prepare("ok go") == .failure(.tooShort))
}

@Test func manualRecordIsRecognisedAndChecked() async throws {
    let r = InboxRecord.manual("I has a idea")
    #expect(r.isManual)
    #expect(r.projectName == "manual")
    let e = FakeEngine()
    let out = try await CheckPipeline(engine: e).run(r)
    #expect(e.calls == ["I has a idea"])
    guard case .checked = out else { Issue.record("got \(out)"); return }
}

@Test func manualEntriesDoNotCountForBadge() {
    #expect(EntryState.badgeCount([EntrySummary(status: .checked, categories: [.grammar], seen: false, isManual: true)]) == 0)
}
