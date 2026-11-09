import Foundation
import Testing
@testable import LectorCore

func record(entrypoint: String?, attended: String?, prompt: String = "fix the bug please now", cwd: String = "/Users/me/dev/my-app", id: String = "p1") -> InboxRecord {
    InboxRecord(promptId: id, sessionId: "s1", cwd: cwd, prompt: prompt,
                timestamp: Date(timeIntervalSince1970: 0), entrypoint: entrypoint, attended: attended)
}

@Test func decodesHookLine() throws {
    let line = #"{"prompt_id":"p1","session_id":"s1","cwd":"/Users/me/dev/my-app","prompt":"fix the bug","timestamp":"2026-11-09T10:00:00Z","entrypoint":"cli","attended":"1"}"#
    let r = try InboxRecord.decoder.decode(InboxRecord.self, from: Data(line.utf8))
    #expect(r.promptId == "p1")
    #expect(r.projectName == "my-app")
    #expect(r.isInteractive)
}

@Test func decodesNullEnv() throws {
    let line = #"{"prompt_id":"p1","session_id":"s1","cwd":"/a","prompt":"x","timestamp":"2026-11-09T10:00:00Z","entrypoint":null,"attended":null}"#
    let r = try InboxRecord.decoder.decode(InboxRecord.self, from: Data(line.utf8))
    #expect(r.entrypoint == nil)
    #expect(r.isInteractive)
}

@Test(arguments: [("sdk-cli", "0"), ("sdk-ts", "1"), ("cli", "0")])
func nonInteractive(ep: String, att: String) {
    #expect(!record(entrypoint: ep, attended: att).isInteractive)
}

@Test func missingEnvIsInteractive() {
    #expect(record(entrypoint: nil, attended: nil).isInteractive)
}

@Test func missingPromptIdGetsStableDerivedId() throws {
    func decode(_ prompt: String, _ ts: String) throws -> InboxRecord {
        let line = #"{"prompt_id":"","session_id":"s1","cwd":"/a","prompt":"\#(prompt)","timestamp":"\#(ts)","entrypoint":"cli","attended":"1"}"#
        return try InboxRecord.decoder.decode(InboxRecord.self, from: Data(line.utf8))
    }
    let a = try decode("first prompt here", "2026-11-09T10:00:00Z")
    let b = try decode("second prompt here", "2026-11-09T10:00:05Z")
    let a2 = try decode("first prompt here", "2026-11-09T10:00:00Z")
    #expect(!a.promptId.isEmpty)
    #expect(a.promptId != b.promptId)
    #expect(a.promptId == a2.promptId)
}

@Test func absentPromptIdKeyGetsDerivedId() throws {
    let line = #"{"session_id":"s1","cwd":"/a","prompt":"hello there","timestamp":"2026-11-09T10:00:00Z"}"#
    #expect(!(try InboxRecord.decoder.decode(InboxRecord.self, from: Data(line.utf8))).promptId.isEmpty)
}
