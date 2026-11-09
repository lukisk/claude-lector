import Foundation
import LectorCore
import Observation
import SwiftData
import SwiftUI
import os

@MainActor @Observable
final class LectorStore {
    let container: ModelContainer
    private(set) var availability: EngineAvailability = .available
    private(set) var engineSummary = ""
    private(set) var badgeCount = 0
    private(set) var pendingCount = 0

    @ObservationIgnored private var engine: any GrammarEngine = GrammarEngineFactory.make(.default)
    @ObservationIgnored private var configError: String?
    @ObservationIgnored private var runtimeUnavailableSince: Date?
    @ObservationIgnored private let reader: InboxReader
    @ObservationIgnored private let configURL: URL
    @ObservationIgnored private var processing = false
    private static let log = Logger(subsystem: "cz.lukisk.ClaudeLector", category: "store")
    /// After the engine reports itself unavailable at runtime (auth, CLI login), wait this long before retrying.
    private static let unavailableBackoff: TimeInterval = 300

    @ObservationIgnored private var watcher: InboxWatcher?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    /// Captured from a view so the global hotkey can open windows.
    @ObservationIgnored var openWindow: OpenWindowAction?

    var context: ModelContext { container.mainContext }

    /// ⌥⌘L from anywhere opens the quick-check window.
    func registerHotKey() {
        hotKey = GlobalHotKey { [weak self] in
            guard let openWindow = self?.openWindow else {
                Self.log.error("hotkey pressed but no openWindow action captured yet")
                return
            }
            Self.log.info("hotkey: opening quick check")
            openWindow(id: QuickCheckWindow.id)
            NSApp.activate()
        }
    }

    enum QuickCheckResult {
        case entry(PromptEntry)
        case message(String)
    }

    /// Checks typed text right away and keeps it in history as a "manual" entry.
    func checkManually(_ text: String) async -> QuickCheckResult {
        let entry = PromptEntry(record: .manual(text))
        entry.seen = true
        context.insert(entry)
        try? context.save()

        updateAvailability()
        if case .unavailable(let reason) = availability {
            return .message("\(reason). It will be checked when the engine is back.")
        }
        do throws(EngineError) {
            entry.apply(try await CheckPipeline(engine: engine).run(entry.record))
        } catch {
            switch EntryState.reaction(to: error, attempts: entry.attempts) {
            case .stopPass(let reason):
                if let reason {
                    availability = .unavailable(reason: reason)
                    runtimeUnavailableSince = .now
                }
                try? context.save()
                return .message("\(reason ?? "The engine had a hiccup"). It stays queued and will be checked later.")
            case .setStatus(let status, let countAttempt):
                if countAttempt { entry.attempts += 1 }
                entry.status = status
            }
        }
        try? context.save()
        refreshCounts()
        switch entry.status {
        case .skipped where entry.skipReasonRaw == SkipReason.notEnglish.rawValue:
            context.delete(entry)
            try? context.save()
            return .message("This doesn't look like English.")
        case .skipped:
            context.delete(entry)
            try? context.save()
            return .message("Nothing to check here.")
        case .refused:
            return .message("The model declined to check this text.")
        default:
            return .entry(entry)
        }
    }

    func startWatching() {
        watcher = InboxWatcher(directory: InboxReader.defaultURL.deletingLastPathComponent()) { [weak self] in
            await self?.ingest()
            await self?.processPending()
        }
    }

    /// Re-reads config.json and immediately retries queued prompts.
    func reloadConfigAndProcess() {
        reloadConfig()
        Task { await processPending() }
    }

    init(container: ModelContainer, inboxURL: URL = InboxReader.defaultURL, configURL: URL = EngineConfig.defaultURL) {
        self.container = container
        self.reader = InboxReader(inboxURL: inboxURL)
        self.configURL = configURL
        reloadConfig()
        refreshCounts()
    }

    static func makeContainer() throws -> ModelContainer {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/ClaudeLector")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try ModelContainer(for: PromptEntry.self,
                                  configurations: ModelConfiguration(url: dir.appending(path: "history.store")))
    }

    // MARK: - Config

    func reloadConfig() {
        runtimeUnavailableSince = nil
        switch EngineConfig.load(from: configURL) {
        case .success(let config):
            engine = GrammarEngineFactory.make(config)
            engineSummary = config.summary
            configError = nil
        case .failure(.invalid(let message)):
            engineSummary = "invalid config"
            configError = message
        }
        updateAvailability()
    }

    private func updateAvailability() {
        if let configError {
            availability = .unavailable(reason: configError)
        } else if case .unavailable = availability, let since = runtimeUnavailableSince,
                  Date.now.timeIntervalSince(since) < Self.unavailableBackoff {
            // keep the runtime reason until the backoff expires
        } else {
            runtimeUnavailableSince = nil
            availability = engine.availability
        }
    }

    // MARK: - Pipeline

    /// Moves everything from the inbox into the store as pending entries.
    func ingest() async {
        do {
            let batch = try await reader.drain()
            if !batch.records.isEmpty {
                let existing = Set(try context.fetch(FetchDescriptor<PromptEntry>()).map(\.promptId))
                for r in batch.records where !existing.contains(r.promptId) {
                    context.insert(PromptEntry(record: r))
                }
                try context.save()
            }
            try reader.commit(batch)   // only after the records are stored
        } catch {
            Self.log.error("ingest failed: \(String(describing: error), privacy: .public)")
        }
        refreshCounts()
    }

    /// Checks pending entries oldest-first, one at a time, while the engine is available.
    func processPending() async {
        guard !processing else { return }
        processing = true
        defer { processing = false; refreshCounts() }

        updateAvailability()
        guard availability == .available else { return }

        let pending = FetchDescriptor<PromptEntry>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.timestamp)])
        guard let entries = try? context.fetch(pending) else { return }

        let pipeline = CheckPipeline(engine: engine)
        for entry in entries {
            do throws(EngineError) {
                entry.apply(try await pipeline.run(entry.record))
            } catch {
                Self.log.warning("check failed: \(String(describing: error), privacy: .private)")
                switch EntryState.reaction(to: error, attempts: entry.attempts) {
                case .stopPass(let reason):
                    if let reason {
                        availability = .unavailable(reason: reason)
                        runtimeUnavailableSince = .now
                    }
                    return   // retried on the next trigger (≤ 30 s); no attempt burned
                case .setStatus(let status, let countAttempt):
                    if countAttempt { entry.attempts += 1 }
                    entry.status = status
                }
            }
            try? context.save()
            refreshCounts()
        }
    }

    // MARK: - UI actions

    func refreshCounts() {
        let all = (try? context.fetch(FetchDescriptor<PromptEntry>())) ?? []
        badgeCount = EntryState.badgeCount(all.map(\.summary))
        pendingCount = all.filter { $0.status == .pending }.count
    }

    /// Marks everything seen and returns the ids that were unseen, so the list can dot them once.
    func markAllSeen() -> Set<String> {
        Self.log.info("markAllSeen")
        let unseen = (try? context.fetch(FetchDescriptor<PromptEntry>(predicate: #Predicate { !$0.seen }))) ?? []
        let ids = Set(unseen.filter { $0.status == .checked }.map(\.promptId))
        unseen.filter { $0.status != .pending }.forEach { $0.seen = true }
        try? context.save()
        refreshCounts()
        return ids
    }

    func markSeen(_ entry: PromptEntry) {
        guard !entry.seen else { return }
        entry.seen = true
        try? context.save()
        refreshCounts()
    }

    func clearHistory() {
        try? context.delete(model: PromptEntry.self)
        try? context.save()
        refreshCounts()
    }
}
