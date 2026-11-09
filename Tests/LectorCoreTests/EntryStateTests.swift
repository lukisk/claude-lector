import Testing
@testable import LectorCore

@Test func badgeCountsOnlyUnseenCheckedWithGrammar() {
    let entries = [
        EntrySummary(status: .checked, categories: [.grammar], seen: false),          // counts
        EntrySummary(status: .checked, categories: [.grammar, .typo], seen: false),   // counts
        EntrySummary(status: .checked, categories: [.grammar], seen: true),           // seen
        EntrySummary(status: .checked, categories: [.typo], seen: false),             // typo only
        EntrySummary(status: .checked, categories: [.natural], seen: false),          // natural only
        EntrySummary(status: .checked, categories: [], seen: false),                  // clean
        EntrySummary(status: .skipped, categories: [], seen: false),
        EntrySummary(status: .pending, categories: [], seen: false),
        EntrySummary(status: .refused, categories: [], seen: false),
    ]
    #expect(EntryState.badgeCount(entries) == 2)
}

@Test func badReplyCountsAttemptsThenFails() {
    #expect(EntryState.reaction(to: .badReply("x"), attempts: 0) == .setStatus(.pending, countAttempt: true))
    #expect(EntryState.reaction(to: .badReply("x"), attempts: 1) == .setStatus(.pending, countAttempt: true))
    #expect(EntryState.reaction(to: .badReply("x"), attempts: 2) == .setStatus(.failed, countAttempt: true))
}

@Test func engineWideErrorsStopThePassWithoutTouchingEntries() {
    #expect(EntryState.reaction(to: .transient("500"), attempts: 2) == .stopPass(unavailable: nil))
    #expect(EntryState.reaction(to: .unavailable("VPN off"), attempts: 2) == .stopPass(unavailable: "VPN off"))
}

@Test func refusedIsFinal() {
    #expect(EntryState.reaction(to: .refused, attempts: 0) == .setStatus(.refused, countAttempt: false))
}

@Test func failedEntriesDoNotCountForBadge() {
    #expect(EntryState.badgeCount([EntrySummary(status: .failed, categories: [], seen: false)]) == 0)
}
