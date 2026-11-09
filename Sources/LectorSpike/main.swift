// Quality gate: compare a configured engine (or Apple's model with --apple) with subscription · haiku on the user's real prompts.
// Usage: swift run LectorSpike [--limit 25] [--config path] [--apple]
import Foundation
import LectorCore

struct Candidate { let text: String; let date: String }

let args = CommandLine.arguments
let limit = args.firstIndex(of: "--limit").flatMap { Int(args[$0 + 1]) } ?? 15

func loadCandidates() -> [Candidate] {
    let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    let skipPrefixes = ["<command-", "<task-notification", "<local-command", "<system-reminder", "<bash-", "Caveat:", "[Request interrupted", "This session is being continued"]
    var seen = Set<String>()
    var out: [Candidate] = []
    let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    for dir in dirs {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jsonl" {
            guard let data = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in data.split(separator: "\n") {
                guard line.contains("\"type\":\"user\""),
                      let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      obj["type"] as? String == "user", obj["isMeta"] as? Bool != true,
                      obj["isSidechain"] as? Bool != true, obj["entrypoint"] as? String == "cli",
                      let msg = obj["message"] as? [String: Any], let text = msg["content"] as? String
                else { continue }
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if skipPrefixes.contains(where: t.hasPrefix) || !seen.insert(t).inserted { continue }
                guard case .success = PromptFilter.prepare(t) else { continue }
                out.append(Candidate(text: t, date: obj["timestamp"] as? String ?? ""))
            }
        }
    }
    return out.sorted { $0.date > $1.date }
}

func fmt(_ issues: [LocatedIssue]) -> String {
    issues.isEmpty ? "_no issues_" : issues.map {
        "- **\($0.issue.category.rawValue)** · `\($0.issue.original)` → `\($0.issue.replacement)` — \($0.issue.explanation)"
    }.joined(separator: "\n")
}

func overlaps(_ a: LocatedIssue, _ b: LocatedIssue) -> Bool { a.offset < b.offset + b.length && b.offset < a.offset + a.length }

// Candidate: the configured engine (or Apple's model with --apple). Baseline: subscription · haiku.
let configURL = args.firstIndex(of: "--config").map { URL(fileURLWithPath: args[$0 + 1]) } ?? EngineConfig.defaultURL
let config: EngineConfig
switch EngineConfig.load(from: configURL) {
case .success(let c): config = c
case .failure(let e): print("Config error: \(e)"); exit(1)
}
let engine: any GrammarEngine = args.contains("--apple") ? AppleGrammarEngine() : GrammarEngineFactory.make(config)
let candidateName = args.contains("--apple") ? "Apple on-device" : config.summary
let baseline = ClaudeCLIGrammarEngine(model: "haiku")
guard engine.availability == .available else { print("Engine unavailable: \(engine.availability)"); exit(1) }

let candidates = Array(loadCandidates().prefix(limit))
print("Checking \(candidates.count) prompts…")
var report = "# Quality gate report\n\nCandidate: \(candidateName) · baseline: subscription · haiku.\n\nGenerated \(Date.now.formatted()). \(candidates.count) most recent English prompts.\n\n"
var rows: [String] = []
var candidateFailed = 0
var totals = (apple: 0, haiku: 0, appleOnlyGrammar: 0, haikuOnlyGrammar: 0, haikuFailed: 0)

for (n, c) in candidates.enumerated() {
    guard case .success(let prepared) = PromptFilter.prepare(c.text) else { continue }
    var apple: [LocatedIssue] = [], claude: [LocatedIssue] = []
    var shift = 0
    var haikuFailed = false
    for chunk in prepared.chunks {
        let a: [Issue]
        do { a = try await engine.check(chunk).issues } catch { a = []; candidateFailed += 1; print("    candidate error: \(error)") }
        let h = try? await baseline.check(chunk).issues
        if h == nil { haikuFailed = true }
        apple += IssueLocator.locate(a, in: chunk).map { var x = $0; x.offset += shift; return x }
        claude += IssueLocator.locate(h ?? [], in: chunk).map { var x = $0; x.offset += shift; return x }
        shift += chunk.count + 2
    }
    let appleOnly = apple.filter { a in a.issue.category == .grammar && !claude.contains { overlaps(a, $0) } }
    let haikuOnly = claude.filter { h in h.issue.category == .grammar && !apple.contains { overlaps(h, $0) } }
    totals.apple += apple.count; totals.haiku += claude.count
    totals.appleOnlyGrammar += appleOnly.count; totals.haikuOnlyGrammar += haikuOnly.count
    if haikuFailed { totals.haikuFailed += 1 }
    rows.append("| \(n + 1) | \(apple.count) | \(claude.count)\(haikuFailed ? " ⚠︎" : "") | \(appleOnly.count) | \(haikuOnly.count) |")
    report += "## \(n + 1)\n\n> " + prepared.chunks.joined(separator: "\n\n").replacingOccurrences(of: "\n", with: "\n> ") + "\n\n"
    report += "**\(candidateName)**\n\n\(fmt(apple))\n\n**Baseline (subscription · haiku)**\(haikuFailed ? " (call failed)" : "")\n\n\(fmt(claude))\n\n"
    print("  \(n + 1)/\(candidates.count) apple=\(apple.count) haiku=\(claude.count)")
}

report += """
## Summary

| # | Candidate issues | Baseline issues | Candidate-only grammar (possible false positive) | Baseline-only grammar (possible miss) |
|---|---|---|---|---|
\(rows.joined(separator: "\n"))
| **Σ** | \(totals.apple) | \(totals.haiku) | \(totals.appleOnlyGrammar) | \(totals.haikuOnlyGrammar) |

Candidate: \(candidateName). Candidate calls failed: \(candidateFailed). Baseline calls failed: \(totals.haikuFailed)
"""
try report.write(to: URL(fileURLWithPath: "spike/report.md"), atomically: true, encoding: .utf8)
print("Wrote spike/report.md")
