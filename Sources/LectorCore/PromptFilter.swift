import Foundation
import NaturalLanguage

public enum SkipReason: String, Codable, Sendable, Error {
    case nonInteractive, slashCommand, tooShort, notEnglish, noProse
}

public struct PreparedPrompt: Sendable, Equatable {
    public var chunks: [String]
    public var truncated: Bool
}

public enum CheckMode: Sendable {
    /// Captured from Claude Code: skip anything that isn't clearly the user's English prose.
    case automatic
    /// Typed into the quick-check field: the user wants it checked, so only code and
    /// non-English text are filtered out.
    case manual
}

/// Turns a raw prompt into the prose chunks worth grammar-checking.
public enum PromptFilter {
    public static func prepare(_ prompt: String, mode: CheckMode = .automatic, budget: Int = 3000, chunkLimit: Int = 1000) -> Result<PreparedPrompt, SkipReason> {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .automatic, trimmed.range(of: #"^/[A-Za-z0-9:_-]+(\s|$)"#, options: .regularExpression) != nil {
            return .failure(.slashCommand)
        }
        let stripped = stripNonProse(trimmed)
        let words = wordCount(stripped)
        switch mode {
        case .automatic:
            if words < 3 { return .failure(.tooShort) }
            let paragraphs = proseParagraphs(stripped)
            if paragraphs.isEmpty { return .failure(.noProse) }
            guard let english = englishParagraphs(paragraphs) else { return .failure(.notEnglish) }
            return .success(pack(english, budget: budget, chunkLimit: chunkLimit))
        case .manual:
            if words == 0 { return .failure(.tooShort) }
            // Prose paragraphs if there are any; otherwise whatever text the user typed.
            let prose = proseParagraphs(stripped)
            let paragraphs = prose.isEmpty
                ? stripped.split(separator: /\n[ \t]*\n/).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                : prose
            // Language detection is meaningless for one or two words.
            if words < 3 { return .success(pack(paragraphs, budget: budget, chunkLimit: chunkLimit)) }
            guard let english = englishParagraphs(paragraphs) else { return .failure(.notEnglish) }
            return .success(pack(english, budget: budget, chunkLimit: chunkLimit))
        }
    }

    // MARK: - Stripping

    static let placeholders = ["⟨code⟩", "⟨path⟩", "⟨link⟩", foreignPlaceholder]
    static let foreignPlaceholder = "⟨foreign⟩"

    /// Blocks Claude Code delivers through the user-prompt channel although the user didn't
    /// type them: subagent reports, background-task notices, system reminders and messages
    /// from other sessions. Only complete blocks match, so a prompt that merely mentions
    /// `<agent-message …>` keeps its text.
    public static func stripMachineBlocks(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<(agent-message|task-notification|cross-session-message|system-reminder)\b[^>]*>[\s\S]*?</\1>"#,
            with: "\n\n", options: .regularExpression)
    }

    /// True when the prompt consists only of such injected blocks.
    public static func isMachineMessage(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && stripMachineBlocks(trimmed).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Removes fenced code entirely and replaces inline code, URLs and paths with
    /// placeholders so the remaining sentence stays grammatical.
    static func stripNonProse(_ text: String) -> String {
        var s = stripMachineBlocks(text)
        // Pasted text was written by someone else — not the user's English.
        s = s.replacingOccurrences(of: #"<pasted_content[^>]*>[\s\S]*?(</pasted_content[^>]*>|$)"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"```[\s\S]*?(```|$)"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`[^`\n]+`"#, with: "⟨code⟩", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b[a-zA-Z][a-zA-Z0-9+.-]*://\S+"#, with: "⟨link⟩", options: .regularExpression)
        // ~/x, /abs/path, ./rel, and word/word paths (at least one slash, no spaces)
        s = s.replacingOccurrences(of: #"(?<![\w⟩])(~|\.{1,2})?/[^\s,;:()\[\]"']+"#, with: "⟨path⟩", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b[\w.-]+/[\w./-]*[\w-]"#, with: "⟨path⟩", options: .regularExpression)
        return s
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace)
            .filter { w in !placeholders.contains(where: { w.contains($0) }) && w.contains(where: \.isLetter) }
            .count
    }

    // MARK: - Prose detection

    static func proseParagraphs(_ text: String) -> [String] {
        text.split(separator: /\n[ \t]*\n/).map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isProse($0) }
    }

    static func isProse(_ paragraph: String) -> Bool {
        let lines = paragraph.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return false }
        let proseLines = lines.filter(isProseLine).count
        return Double(proseLines) / Double(lines.count) >= 0.6
    }

    private static var logLine: some RegexComponent { #/^\s*(at\s|\d{4}-\d{2}-\d{2}|\d{2}:\d{2}:\d{2}|\||[\w.]*(Error|Exception)\b:|Traceback|File ")/# }

    static func isProseLine(_ line: String) -> Bool {
        if line.firstMatch(of: logLine) != nil { return false }
        let letterWords = line.split(whereSeparator: \.isWhitespace).filter { word in
            let core = word.trimmingCharacters(in: .punctuationCharacters)
            return !core.isEmpty && core.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }
        }
        return letterWords.count >= 3
    }

    /// The paragraphs with clearly foreign clauses masked, or nil when the text isn't mostly English.
    /// Masking comes first: a few words with diacritics (a quoted Czech title) otherwise make the
    /// recognizer call a long English prompt Czech.
    static func englishParagraphs(_ paragraphs: [String]) -> [String]? {
        let masked = paragraphs.map(maskForeignClauses)
        let englishWords = wordCount(masked.joined(separator: " "))
        let allWords = wordCount(paragraphs.joined(separator: " "))
        guard englishWords >= 3, englishWords * 2 >= allWords,
              isEnglish(masked.joined(separator: "\n\n")) else { return nil }
        return masked
    }

    /// English overall (≥ 0.7), ignoring tokens with digits (mr235, pr120 skew short texts toward English).
    static func isEnglish(_ text: String) -> Bool {
        englishProbability(languageWords(text).joined(separator: " ")) >= 0.7
    }

    /// Replaces clauses that are clearly another language — a quoted Czech title, a colleague's
    /// Slovak sentence — with ⟨foreign⟩, so the English around them can still be checked.
    static func maskForeignClauses(_ text: String) -> String {
        var out = ""
        var clause = ""
        func flush() {
            if isForeignClause(clause) {
                let lead = clause.prefix(while: \.isWhitespace)
                let trail = clause.reversed().prefix(while: \.isWhitespace)
                out += lead + foreignPlaceholder + String(trail.reversed())
            } else {
                out += clause
            }
            clause = ""
        }
        for ch in text {
            if ",;?.!\n".contains(ch) { flush(); out.append(ch) } else { clause.append(ch) }
        }
        flush()
        return out
    }

    private static func isForeignClause(_ clause: String) -> Bool {
        let words = languageWords(clause)
        guard words.count >= 3 else { return false }
        let r = NLLanguageRecognizer()
        r.processString(words.joined(separator: " "))
        guard let lang = r.dominantLanguage, lang != .english else { return false }
        return (r.languageHypotheses(withMaximum: 1)[lang] ?? 0) >= 0.8
    }

    private static func languageWords(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
            .filter { !$0.contains(where: \.isNumber) && !placeholders.contains(where: $0.contains) }
    }

    private static func englishProbability(_ text: String) -> Double {
        let r = NLLanguageRecognizer()
        r.processString(text)
        guard r.dominantLanguage == .english else { return 0 }
        return r.languageHypotheses(withMaximum: 1)[.english] ?? 0
    }

    // MARK: - Chunking

    static func pack(_ paragraphs: [String], budget: Int, chunkLimit: Int) -> PreparedPrompt {
        let pieces = paragraphs.flatMap { $0.count <= chunkLimit ? [$0] : splitSentences($0, limit: chunkLimit) }
        var chunks: [String] = []
        var current = ""
        var used = 0
        var truncated = false
        for piece in pieces {
            if used + piece.count > budget { truncated = true; break }
            used += piece.count
            if current.isEmpty {
                current = piece
            } else if current.count + 2 + piece.count <= chunkLimit {
                current += "\n\n" + piece
            } else {
                chunks.append(current)
                current = piece
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return PreparedPrompt(chunks: chunks, truncated: truncated)
    }

    /// Splits an over-long paragraph into pieces of whole sentences, each ≤ `limit`.
    static func splitSentences(_ paragraph: String, limit: Int) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            let s = paragraph[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(contentsOf: hardSplit(s, limit: limit)) }
            return true
        }
        var out: [String] = []
        var current = ""
        for s in sentences {
            if current.isEmpty { current = s }
            else if current.count + 1 + s.count <= limit { current += " " + s }
            else { out.append(current); current = s }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func hardSplit(_ s: String, limit: Int) -> [String] {
        guard s.count > limit else { return [s] }
        var out: [String] = []
        var rest = Substring(s)
        while rest.count > limit {
            let cut = rest.index(rest.startIndex, offsetBy: limit)
            let space = rest[..<cut].lastIndex(where: \.isWhitespace) ?? cut
            out.append(String(rest[..<space]).trimmingCharacters(in: .whitespaces))
            rest = rest[space...].drop(while: \.isWhitespace)
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }
}
