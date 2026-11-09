import Foundation

public enum ConfigError: Error, Equatable, Sendable {
    case invalid(String)
}

/// `~/.config/claude-lector/config.json`
public struct EngineConfig: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case subscription, proxy }

    public struct Subscription: Codable, Equatable, Sendable {
        public var model: String
        public init(model: String) { self.model = model }
    }

    public struct Proxy: Codable, Equatable, Sendable {
        public var baseURL: String
        public var token: String
        public var tokenHeader: String?
        public var model: String

        public init(baseURL: String, token: String, tokenHeader: String?, model: String) {
            self.baseURL = baseURL
            self.token = token
            self.tokenHeader = tokenHeader
            self.model = model
        }

        enum CodingKeys: String, CodingKey {
            case baseURL = "base_url", token, tokenHeader = "token_header", model
        }
    }

    public var engine: Kind
    public var subscription: Subscription?
    public var proxy: Proxy?

    public init(engine: Kind, subscription: Subscription? = nil, proxy: Proxy? = nil) {
        self.engine = engine
        self.subscription = subscription
        self.proxy = proxy
    }

    public static let `default` = EngineConfig(engine: .subscription, subscription: .init(model: "haiku"))

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/claude-lector/config.json")
    }

    public var summary: String {
        switch engine {
        case .subscription: "subscription · \(subscription?.model ?? "haiku")"
        case .proxy: "proxy · \(proxy?.model ?? "?")"
        }
    }

    public static func load(from url: URL = defaultURL) -> Result<EngineConfig, ConfigError> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(.default) }
        let config: EngineConfig
        do {
            config = try JSONDecoder().decode(EngineConfig.self, from: Data(contentsOf: url))
        } catch {
            return .failure(.invalid("config.json is not valid: \(error.localizedDescription)"))
        }
        switch config.engine {
        case .subscription:
            if let m = config.subscription?.model, m.isEmpty { return .failure(.invalid("subscription.model is empty")) }
        case .proxy:
            guard let p = config.proxy else { return .failure(.invalid("engine is proxy but the proxy section is missing")) }
            if URL(string: p.baseURL)?.scheme == nil { return .failure(.invalid("proxy.base_url is not a URL")) }
            if p.token.isEmpty { return .failure(.invalid("proxy.token is empty")) }
            if p.model.isEmpty { return .failure(.invalid("proxy.model is empty")) }
        }
        return .success(config)
    }
}
