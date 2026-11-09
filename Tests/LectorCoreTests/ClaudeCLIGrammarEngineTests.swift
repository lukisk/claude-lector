import Foundation
import Testing
@testable import LectorCore

private func script(_ body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "fake-claude-\(UUID().uuidString).sh")
    try ("#!/bin/bash\n" + body).write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private let reply = #"{"correctedText":"I went","issues":[{"original":"I go","replacement":"I went","category":"grammar","explanation":"Past tense."}]}"#

@Test func parsesReplyFromCLI() async throws {
    let e = ClaudeCLIGrammarEngine(model: "haiku", claudePath: try script("cat >/dev/null\necho '\(reply)'"), timeout: 10)
    #expect(try await e.check("I go").issues.count == 1)
}

@Test func childIgnoringSigtermDoesNotWedge() async throws {
    let e = ClaudeCLIGrammarEngine(model: "haiku", claudePath: try script("trap '' TERM\nsleep 60"), timeout: 1, killGrace: 1)
    let start = Date.now
    do { _ = try await e.check("I go"); Issue.record("expected timeout") }
    catch { if case .transient = error {} else { Issue.record("got \(error)") } }
    #expect(Date.now.timeIntervalSince(start) < 8)
}

@Test func grandchildHoldingStdoutDoesNotBlock() async throws {
    let e = ClaudeCLIGrammarEngine(model: "haiku", claudePath: try script("cat >/dev/null\necho '\(reply)'\nsleep 30 &\nexit 0"), timeout: 20)
    let start = Date.now
    #expect(try await e.check("I go").issues.count == 1)
    #expect(Date.now.timeIntervalSince(start) < 5)
}

@Test func childExitingWithoutReadingStdinDoesNotCrash() async throws {
    let e = ClaudeCLIGrammarEngine(model: "haiku", claudePath: try script("exit 3"), timeout: 5)
    do { _ = try await e.check(String(repeating: "long text ", count: 20_000)); Issue.record("expected throw") }
    catch { if case .transient = error {} else { Issue.record("got \(error)") } }
}
