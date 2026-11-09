import Foundation
import Testing
@testable import LectorCore

private func line(_ id: String, _ prompt: String = "hello there friend") -> String {
    #"{"prompt_id":"\#(id)","session_id":"s","cwd":"/a/b","prompt":"\#(prompt)","timestamp":"2026-11-09T10:00:00Z","entrypoint":"cli","attended":"1"}"#
}

private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func files(in dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

@Test func drainsAndRemovesFile() async throws {
    let dir = try tempDir()
    let inbox = dir.appending(path: "inbox.jsonl")
    try (line("a") + "\n" + line("b") + "\n").write(to: inbox, atomically: true, encoding: .utf8)
    let reader = InboxReader(inboxURL: inbox, graceDelay: .zero)
    let batch = try await reader.drain()
    #expect(batch.records.map(\.promptId) == ["a", "b"])
    try reader.commit(batch)
    #expect(files(in: dir).isEmpty)
}

@Test func emptyWhenNoInbox() async throws {
    let dir = try tempDir()
    #expect(try await InboxReader(inboxURL: dir.appending(path: "inbox.jsonl"), graceDelay: .zero).drain().records.isEmpty)
}

@Test func emptyWhenDirectoryMissing() async throws {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)/inbox.jsonl")
    #expect(try await InboxReader(inboxURL: inbox, graceDelay: .zero).drain().records.isEmpty)
}

@Test func skipsMalformedKeepsOthers() async throws {
    let dir = try tempDir()
    let inbox = dir.appending(path: "inbox.jsonl")
    try ("garbage\n" + line("ok") + "\n" + #"{"prompt_id":"#).write(to: inbox, atomically: true, encoding: .utf8)
    let r = try await InboxReader(inboxURL: inbox, graceDelay: .zero).drain().records
    #expect(r.map(\.promptId) == ["ok"])
}

@Test func lastLineWithoutNewlineIsParsed() async throws {
    let dir = try tempDir()
    let inbox = dir.appending(path: "inbox.jsonl")
    try (line("a") + "\n" + line("b")).write(to: inbox, atomically: true, encoding: .utf8)
    #expect(try await InboxReader(inboxURL: inbox, graceDelay: .zero).drain().records.map(\.promptId) == ["a", "b"])
}

@Test func picksUpLeftoverProcessingFile() async throws {
    let dir = try tempDir()
    try (line("old") + "\n").write(to: dir.appending(path: "inbox.processing-x.jsonl"), atomically: true, encoding: .utf8)
    try (line("new") + "\n").write(to: dir.appending(path: "inbox.jsonl"), atomically: true, encoding: .utf8)
    let reader = InboxReader(inboxURL: dir.appending(path: "inbox.jsonl"), graceDelay: .zero)
    let batch = try await reader.drain()
    #expect(Set(batch.records.map(\.promptId)) == ["old", "new"])
    try reader.commit(batch)
    #expect(files(in: dir).isEmpty)
}

@Test func appendAfterRenameGoesToNewInbox() async throws {
    let dir = try tempDir()
    let inbox = dir.appending(path: "inbox.jsonl")
    let reader = InboxReader(inboxURL: inbox, graceDelay: .zero)
    try (line("a") + "\n").write(to: inbox, atomically: true, encoding: .utf8)
    try reader.commit(try await reader.drain())
    try (line("b") + "\n").write(to: inbox, atomically: true, encoding: .utf8)
    #expect(try await reader.drain().records.map(\.promptId) == ["b"])
}

@Test func dedupesWithinOneDrain() async throws {
    let dir = try tempDir()
    let inbox = dir.appending(path: "inbox.jsonl")
    try (line("a") + "\n" + line("a") + "\n").write(to: inbox, atomically: true, encoding: .utf8)
    #expect(try await InboxReader(inboxURL: inbox, graceDelay: .zero).drain().records.count == 1)
}

@Test func uncommittedBatchIsRedeliveredAfterCrash() async throws {
    let dir = try tempDir()
    let inbox = dir.appending(path: "inbox.jsonl")
    try (line("a") + "\n").write(to: inbox, atomically: true, encoding: .utf8)
    _ = try await InboxReader(inboxURL: inbox, graceDelay: .zero).drain()   // app dies before saving
    let again = try await InboxReader(inboxURL: inbox, graceDelay: .zero).drain()
    #expect(again.records.map(\.promptId) == ["a"])
}

@Test func unreadableClaimedFileIsSkipped() async throws {
    let dir = try tempDir()
    try FileManager.default.createDirectory(at: dir.appending(path: "inbox.processing-bad.jsonl"), withIntermediateDirectories: true)
    try (line("ok") + "\n").write(to: dir.appending(path: "inbox.jsonl"), atomically: true, encoding: .utf8)
    let batch = try await InboxReader(inboxURL: dir.appending(path: "inbox.jsonl"), graceDelay: .zero).drain()
    #expect(batch.records.map(\.promptId) == ["ok"])
}
