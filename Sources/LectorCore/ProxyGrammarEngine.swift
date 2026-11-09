import Foundation

/// Grammar checking through the company LLM proxy (Anthropic Messages API).
public final class ProxyGrammarEngine: GrammarEngine {
    let config: EngineConfig.Proxy
    let session: URLSession

    public init(config: EngineConfig.Proxy, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public var availability: EngineAvailability { .available }

    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
        .timedOut, .dnsLookupFailed, .secureConnectionFailed,
    ]

    /// The proxy's own error message (`{"error":{"message":…}}`), or a short excerpt.
    static func errorMessage(_ data: Data) -> String {
        struct Body: Decodable { struct E: Decodable { let message: String }; let error: E }
        if let b = try? JSONDecoder().decode(Body.self, from: data) { return b.error.message }
        return String(decoding: data.prefix(120), as: UTF8.self)
    }

    var endpoint: URL? {
        var base = config.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/v1/messages")
    }

    public func check(_ text: String) async throws(EngineError) -> CheckResult {
        guard let endpoint else { throw .unavailable("proxy.base_url is not a URL") }
        var req = URLRequest(url: endpoint, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let header = config.tokenHeader, !header.isEmpty {
            req.setValue(config.token, forHTTPHeaderField: header)
        } else {
            req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 2048,
            "system": GrammarPrompt.instructions,
            "messages": [["role": "user", "content": GrammarPrompt.userMessage(text)]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw .unavailable("proxy unreachable (VPN or network?)")
        } catch {
            throw .transient("proxy request failed: \(error.localizedDescription)")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 401, 403: throw .unavailable("proxy rejected the token")
        case 429, 500...: throw .transient("proxy returned \(status)")
        default: throw .unavailable("proxy error \(status): \(Self.errorMessage(data))")
        }
        struct Reply: Decodable { struct Block: Decodable { let type: String; let text: String? }; let content: [Block] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw .badReply("unexpected proxy response")
        }
        return try GrammarPrompt.parse(reply.content.compactMap(\.text).joined())
    }
}
