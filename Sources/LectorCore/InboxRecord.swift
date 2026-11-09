import CryptoKit
import Foundation

/// One prompt captured by `hooks/capture-prompt.sh`, as a line in `inbox.jsonl`.
public struct InboxRecord: Codable, Sendable, Equatable {
    public var promptId: String
    public var sessionId: String
    public var cwd: String
    public var prompt: String
    public var timestamp: Date
    public var entrypoint: String?
    public var attended: String?

    public init(promptId: String, sessionId: String, cwd: String, prompt: String,
                timestamp: Date, entrypoint: String?, attended: String?) {
        self.promptId = promptId
        self.sessionId = sessionId
        self.cwd = cwd
        self.prompt = prompt
        self.timestamp = timestamp
        self.entrypoint = entrypoint
        self.attended = attended
    }

    enum CodingKeys: String, CodingKey {
        case promptId = "prompt_id", sessionId = "session_id", cwd, prompt, timestamp, entrypoint, attended
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        prompt = try c.decode(String.self, forKey: .prompt)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        entrypoint = try c.decodeIfPresent(String.self, forKey: .entrypoint)
        attended = try c.decodeIfPresent(String.self, forKey: .attended)
        let id = try c.decodeIfPresent(String.self, forKey: .promptId) ?? ""
        // Older Claude Code versions don't send prompt_id; without a fallback every
        // prompt after the first would be deduplicated away.
        promptId = id.isEmpty ? Self.derivedId(sessionId: sessionId, timestamp: timestamp, prompt: prompt) : id
    }

    static func derivedId(sessionId: String, timestamp: Date, prompt: String) -> String {
        let digest = SHA256.hash(data: Data("\(sessionId)|\(timestamp.timeIntervalSince1970)|\(prompt)".utf8))
        return "derived-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Headless `claude -p` / SDK runs report `sdk-*` entrypoints or `attended == "0"`.
    /// Missing values are treated as interactive (better noise than dropping real prompts).
    public var isInteractive: Bool {
        if let entrypoint, entrypoint.hasPrefix("sdk") { return false }
        return attended != "0"
    }

    public var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
