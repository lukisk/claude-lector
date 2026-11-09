import Foundation
import Testing
@testable import LectorCore

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var failWith: URLError?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { s in
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            return d
        }
        if let error = Self.failWith {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let (status, data) = Self.handler!(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let c = URLSessionConfiguration.ephemeral
    c.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: c)
}

private let okReply = #"{"content":[{"type":"text","text":"{\"correctedText\":\"I went\",\"issues\":[{\"original\":\"I go\",\"replacement\":\"I went\",\"category\":\"grammar\",\"explanation\":\"Past tense.\"}]}"}]}"#

private func engine() -> ProxyGrammarEngine {
    ProxyGrammarEngine(config: .init(baseURL: "https://p.example", token: "t", tokenHeader: nil, model: "m"), session: stubSession())
}

private func caught(_ e: ProxyGrammarEngine) async -> EngineError? {
    do { _ = try await e.check("I go"); return nil } catch { return error }
}

@Suite(.serialized) struct ProxyGrammarEngineTests {
    init() { StubProtocol.failWith = nil }

    @Test func unknownModelIsUnavailableWithProxyMessage() async {
        StubProtocol.handler = { _ in (404, Data(#"{"error":{"message":"model glm-x not found"}}"#.utf8)) }
        #expect(await caught(engine()) == .unavailable("proxy error 404: model glm-x not found"))
    }

    @Test func rateLimitIsTransient() async {
        StubProtocol.handler = { _ in (429, Data("{}".utf8)) }
        guard case .transient = await caught(engine()) else { Issue.record("not transient"); return }
    }

    @Test func offlineIsUnavailable() async {
        StubProtocol.failWith = URLError(.cannotFindHost)
        guard case .unavailable = await caught(engine()) else { Issue.record("not unavailable"); return }
        StubProtocol.failWith = nil
    }

    @Test func garbled200IsBadReply() async {
        StubProtocol.handler = { _ in (200, Data(#"{"content":[{"type":"text","text":"no json here"}]}"#.utf8)) }
        guard case .badReply = await caught(engine()) else { Issue.record("not badReply"); return }
    }

    @Test func postsToMessagesWithBearer() async throws {
        StubProtocol.handler = { _ in (200, Data(okReply.utf8)) }
        let e = ProxyGrammarEngine(config: .init(baseURL: "https://p.example/", token: "tok", tokenHeader: nil, model: "claude-haiku-4-5"), session: stubSession())
        let r = try await e.check("I go")
        #expect(r.issues.count == 1)
        let req = try #require(StubProtocol.lastRequest)
        #expect(req.url?.absoluteString == "https://p.example/v1/messages")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try #require(StubProtocol.lastBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["model"] as? String == "claude-haiku-4-5")
    }

    @Test func customTokenHeaderSendsRawToken() async throws {
        StubProtocol.handler = { _ in (200, Data(okReply.utf8)) }
        let e = ProxyGrammarEngine(config: .init(baseURL: "https://p.example", token: "tok", tokenHeader: "x-api-key", model: "m"), session: stubSession())
        _ = try await e.check("I go")
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "x-api-key") == "tok")
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func unauthorizedIsUnavailable() async {
        StubProtocol.handler = { _ in (401, Data("{}".utf8)) }
        let e = ProxyGrammarEngine(config: .init(baseURL: "https://p.example", token: "bad", tokenHeader: nil, model: "m"), session: stubSession())
        await #expect(throws: EngineError.unavailable("proxy rejected the token")) { try await e.check("I go") }
    }

    @Test func serverErrorIsTransient() async {
        StubProtocol.handler = { _ in (500, Data("oops".utf8)) }
        let e = ProxyGrammarEngine(config: .init(baseURL: "https://p.example", token: "t", tokenHeader: nil, model: "m"), session: stubSession())
        do { _ = try await e.check("I go"); Issue.record("expected throw") }
        catch { if case .transient = error {} else { Issue.record("got \(error)") } }
    }
}
