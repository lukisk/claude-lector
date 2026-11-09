import Foundation
import Testing
@testable import LectorCore

final class FakeEngine: GrammarEngine, @unchecked Sendable {
    var replies: [String: Result<CheckResult, EngineError>] = [:]
    var calls: [String] = []
    var availability: EngineAvailability { .available }
    func check(_ text: String) async throws(EngineError) -> CheckResult {
        calls.append(text)
        switch replies[text] ?? .success(CheckResult(correctedText: text, issues: [])) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

private func ok(_ issues: [LectorCore.Issue]) -> Result<CheckResult, EngineError> { .success(CheckResult(correctedText: "", issues: issues)) }

private let p1 = String(repeating: "This first paragraph is fine and short. ", count: 24).trimmingCharacters(in: .whitespaces) // ~960, so p1 + p2 exceed one 1000-char chunk
private let p2 = "Yesterday I go to the office and it are closed."

@Test func nonInteractiveSkippedWithoutCallingEngine() async throws {
    let e = FakeEngine()
    let out = try await CheckPipeline(engine: e).run(record(entrypoint: "sdk-cli", attended: "0", prompt: p2))
    #expect(out == .skipped(.nonInteractive))
    #expect(e.calls.isEmpty)
}

@Test func filterSkipPassedThrough() async throws {
    let out = try await CheckPipeline(engine: FakeEngine()).run(record(entrypoint: "cli", attended: "1", prompt: "ok go"))
    #expect(out == .skipped(.tooShort))
}

@Test func offsetsShiftAcrossChunks() async throws {
    let e = FakeEngine()
    e.replies[p2] = ok([issue("it are", "it is")])
    let out = try await CheckPipeline(engine: e).run(record(entrypoint: "cli", attended: "1", prompt: p1 + "\n\n" + p2))
    #expect(e.calls == [p1, p2])
    guard case .checked(let text, let issues, let truncated) = out else { Issue.record("not checked: \(out)"); return }
    #expect(text == p1 + "\n\n" + p2)
    #expect(!truncated)
    let local = p2.distance(from: p2.startIndex, to: p2.range(of: "it are")!.lowerBound)
    #expect(issues.map(\.offset) == [p1.count + 2 + local])
}

@Test func onlyOneNaturalAcrossChunks() async throws {
    let e = FakeEngine()
    e.replies[p1] = ok([issue("first paragraph", "opening paragraph", .natural)])
    e.replies[p2] = ok([issue("Yesterday I go", "Yesterday I went", .natural), issue("it are", "it is")])
    let out = try await CheckPipeline(engine: e).run(record(entrypoint: "cli", attended: "1", prompt: p1 + "\n\n" + p2))
    guard case .checked(_, let issues, _) = out else { Issue.record("not checked"); return }
    #expect(issues.filter { $0.issue.category == .natural }.count == 1)
    #expect(issues.count == 2)
}

@Test func truncatedFlagPassedThrough() async throws {
    let para = String(repeating: "This sentence is fine and short. ", count: 25)
    let out = try await CheckPipeline(engine: FakeEngine()).run(record(entrypoint: "cli", attended: "1", prompt: Array(repeating: para, count: 5).joined(separator: "\n\n")))
    guard case .checked(_, _, let truncated) = out else { Issue.record("not checked"); return }
    #expect(truncated)
}

@Test func refusedChunkGivesRefused() async throws {
    let e = FakeEngine()
    e.replies[p2] = .failure(.refused)
    #expect(try await CheckPipeline(engine: e).run(record(entrypoint: "cli", attended: "1", prompt: p2)) == .refused)
}

@Test func transientErrorPropagates() async {
    let e = FakeEngine()
    e.replies[p2] = .failure(.transient("boom"))
    await #expect(throws: EngineError.transient("boom")) {
        try await CheckPipeline(engine: e).run(record(entrypoint: "cli", attended: "1", prompt: p2))
    }
}
