import Foundation

/// Grammar checking through `claude -p`, using the user's Claude subscription.
public final class ClaudeCLIGrammarEngine: GrammarEngine {
    let model: String
    let claudePath: URL?
    let timeout: TimeInterval
    let killGrace: TimeInterval

    public init(model: String, claudePath: URL? = nil, timeout: TimeInterval = 120, killGrace: TimeInterval = 5) {
        self.model = model
        self.claudePath = claudePath ?? Self.findClaude()
        self.timeout = timeout
        self.killGrace = killGrace
    }

    /// GUI apps don't get the shell PATH, so look in the usual install locations.
    static func findClaude() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public var availability: EngineAvailability {
        claudePath == nil ? .unavailable(reason: "claude CLI not found") : .available
    }

    public func check(_ text: String) async throws(EngineError) -> CheckResult {
        guard let claudePath else { throw .unavailable("claude CLI not found") }
        let (status, out, err) = await Self.run(claudePath, args: [
            "-p", "--model", model,
            "--system-prompt", GrammarPrompt.instructions,
            "--no-session-persistence", "--strict-mcp-config", "--tools", "",
            "--settings", #"{"disableAllHooks":true}"#,
            "--output-format", "text",
        ], stdin: GrammarPrompt.userMessage(text), timeout: timeout, killGrace: killGrace)
        guard status == 0 else {
            let msg = (err + out).lowercased()
            if msg.contains("login") || msg.contains("auth") || msg.contains("api key") {
                throw .unavailable("claude CLI is not logged in")
            }
            if msg.contains("usage limit") || msg.contains("rate limit") {
                throw .unavailable("Claude subscription usage limit reached")
            }
            throw .transient(status == Self.timedOutStatus ? "claude timed out" : "claude exited with \(status): \(err.prefix(200))")
        }
        return try GrammarPrompt.parse(out)
    }

    static let timedOutStatus: Int32 = -2

    /// Runs the CLI without ever wedging the caller:
    /// - pipes are read with handlers, so a grandchild holding stdout open can't block us;
    /// - on timeout: SIGTERM, then SIGKILL after `killGrace`, then give up waiting;
    /// - stdin is written with SIGPIPE disabled, so a child that exits early can't kill the app.
    private static func run(_ exe: URL, args: [String], stdin: String, timeout: TimeInterval, killGrace: TimeInterval) async -> (Int32, String, String) {
        await withCheckedContinuation { (cont: CheckedContinuation<(Int32, String, String), Never>) in
            let state = RunState()
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CLAUDE") }
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
            p.standardInput = inPipe
            p.standardOutput = outPipe
            p.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; state.markOutEOF() } else { state.appendOut(d) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { state.appendErr(d) }
            }

            let finish: @Sendable (Int32) -> Void = { status in
                guard let (out, err) = state.finishOnce() else { return }
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: (status, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self)))
            }

            p.terminationHandler = { proc in
                let status = state.timedOut ? timedOutStatus : proc.terminationStatus
                // Let buffered output arrive; don't wait for EOF a grandchild may never send.
                DispatchQueue.global().async {
                    let deadline = Date.now.addingTimeInterval(1)
                    while !state.outEOF && Date.now < deadline { usleep(20_000) }
                    finish(status)
                }
            }

            do { try p.run() } catch {
                finish(-1)
                return
            }

            let writeFD = inPipe.fileHandleForWriting.fileDescriptor
            _ = fcntl(writeFD, F_SETNOSIGPIPE, 1)
            DispatchQueue.global().async {
                try? inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
                try? inPipe.fileHandleForWriting.close()
            }

            let pid = p.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard p.isRunning else { return }
                state.markTimedOut()
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + killGrace) {
                    if p.isRunning { kill(pid, SIGKILL) }
                    // Last resort if even the termination handler never fires.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { finish(timedOutStatus) }
                }
            }
        }
    }
}

/// Thread-safe accumulator for one CLI run.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    private var finished = false
    private var _outEOF = false, _timedOut = false

    func appendOut(_ d: Data) { lock.withLock { out.append(d) } }
    func appendErr(_ d: Data) { lock.withLock { err.append(d) } }
    func markOutEOF() { lock.withLock { _outEOF = true } }
    func markTimedOut() { lock.withLock { _timedOut = true } }
    var outEOF: Bool { lock.withLock { _outEOF } }
    var timedOut: Bool { lock.withLock { _timedOut } }

    /// Returns the collected output the first time only.
    func finishOnce() -> (Data, Data)? {
        lock.withLock {
            guard !finished else { return nil }
            finished = true
            return (out, err)
        }
    }
}

public enum GrammarEngineFactory {
    public static func make(_ config: EngineConfig) -> any GrammarEngine {
        switch config.engine {
        case .subscription:
            return ClaudeCLIGrammarEngine(model: config.subscription?.model ?? "haiku")
        case .proxy:
            // load() guarantees a proxy section for .proxy
            return ProxyGrammarEngine(config: config.proxy ?? .init(baseURL: "", token: "", tokenHeader: nil, model: ""))
        }
    }
}
