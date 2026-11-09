import Foundation

/// Instructions and reply parsing shared by the text-based (LLM) engines.
public enum GrammarPrompt {
    public static let instructions = """
    You are an English teacher checking short messages written by a non-native speaker \
    (a software developer) to an AI coding assistant. Find real English mistakes so the writer can learn.

    Rules:
    - Flag only real mistakes: grammar (tense, articles, prepositions, word order, subject-verb agreement, plurals, question forms) and misspelled words.
    - Casual tone is fine. Do NOT flag: missing final punctuation, spaces before punctuation, lowercase sentence starts or a lowercase "i", short imperative sentences, abbreviations (pr, mr, cr), or informal words.
    - Never change code identifiers, file names, product names, library names, commands or technical terms.
    - Tokens like ⟨code⟩, ⟨path⟩ and ⟨link⟩ stand for removed code; treat them as nouns and never flag them.
    - "original" must be copied verbatim from the input and be as short as possible: the wrong words plus at most two neighbours.
    - category is one of: "grammar", "typo" (misspelled word), "natural" (correct, but a native speaker would phrase it differently).
    - Give at most one "natural" tip, and only when the phrasing is clearly unnatural.
    - Each explanation is one short, plain-English sentence about the rule.
    - If nothing is wrong, return the input unchanged as correctedText and an empty issues list. Do not invent mistakes.

    Reply with ONLY a JSON object, no prose and no code fences, of this shape:
    {"correctedText": "...", "issues": [{"original": "...", "replacement": "...", "category": "grammar", "explanation": "..."}]}
    """

    public static func userMessage(_ text: String) -> String {
        "Check this text:\n\n\(text)"
    }

    private struct Reply: Decodable {
        struct Item: Decodable { let original, replacement, category, explanation: String }
        let correctedText: String?
        let issues: [Item]
    }

    public static func parse(_ reply: String) throws(EngineError) -> CheckResult {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let r = try? JSONDecoder().decode(Reply.self, from: Data(reply[start...end].utf8))
        else { throw .badReply("unparseable reply: \(reply.prefix(200))") }
        let issues = r.issues.compactMap { i in
            IssueCategory(rawValue: i.category).map {
                Issue(original: i.original, replacement: i.replacement, category: $0, explanation: i.explanation)
            }
        }
        return CheckResult(correctedText: r.correctedText ?? "", issues: issues)
    }
}
