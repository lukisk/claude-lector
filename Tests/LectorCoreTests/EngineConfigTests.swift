import Foundation
import Testing
@testable import LectorCore

private func write(_ s: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "cfg-\(UUID().uuidString).json")
    try s.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func missingFileGivesDefault() throws {
    let r = EngineConfig.load(from: URL(fileURLWithPath: "/nonexistent/config.json"))
    #expect(try r.get() == .default)
    #expect(EngineConfig.default.engine == .subscription)
    #expect(EngineConfig.default.subscription?.model == "haiku")
}

@Test func decodesProxyConfig() throws {
    let url = try write(#"{"engine":"proxy","proxy":{"base_url":"https://p.example","token":"t","token_header":"x-api-key","model":"claude-haiku-4-5"}}"#)
    let c = try EngineConfig.load(from: url).get()
    #expect(c.engine == .proxy)
    #expect(c.proxy == EngineConfig.Proxy(baseURL: "https://p.example", token: "t", tokenHeader: "x-api-key", model: "claude-haiku-4-5"))
    #expect(c.summary == "proxy · claude-haiku-4-5")
}

@Test func proxyWithoutTokenFails() throws {
    let url = try write(#"{"engine":"proxy","proxy":{"base_url":"https://p.example","token":"","model":"m"}}"#)
    #expect((try? EngineConfig.load(from: url).get()) == nil)
}

@Test func proxyEngineWithoutProxySectionFails() throws {
    let url = try write(#"{"engine":"proxy"}"#)
    #expect((try? EngineConfig.load(from: url).get()) == nil)
}

@Test func malformedFails() throws {
    let url = try write("{nope")
    #expect((try? EngineConfig.load(from: url).get()) == nil)
}

@Test func subscriptionSummary() {
    #expect(EngineConfig.default.summary == "subscription · haiku")
}
