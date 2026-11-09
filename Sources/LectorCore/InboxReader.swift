import Foundation
import os

/// Consumes `inbox.jsonl`: atomically claims it by renaming, waits a moment for any
/// hook that opened the file just before the rename, parses it and deletes it.
/// A hook writing after the rename simply creates a fresh inbox.
public struct InboxReader: Sendable {
    public let inboxURL: URL
    public let graceDelay: Duration
    private static let log = Logger(subsystem: "cz.lukisk.ClaudeLector", category: "inbox")

    public init(inboxURL: URL, graceDelay: Duration = .seconds(1)) {
        self.inboxURL = inboxURL
        self.graceDelay = graceDelay
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ClaudeLector/inbox.jsonl")
    }

    /// Claims the inbox and returns its records. Files are deleted only by `commit(_:)`,
    /// after the caller has saved the records, so a crash in between redelivers them.
    public func drain() async throws -> InboxBatch {
        let fm = FileManager.default
        let dir = inboxURL.deletingLastPathComponent()
        guard fm.fileExists(atPath: dir.path) else { return InboxBatch(records: [], files: []) }

        // Leftovers from a run that crashed between claiming and committing.
        var claimed = try fm.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("inbox.processing-") && $0.hasSuffix(".jsonl") }
            .sorted()
            .map { dir.appending(path: $0) }

        if fm.fileExists(atPath: inboxURL.path) {
            let target = dir.appending(path: "inbox.processing-\(Date.now.timeIntervalSince1970)-\(UUID().uuidString).jsonl")
            try fm.moveItem(at: inboxURL, to: target)
            claimed.append(target)
            if graceDelay > .zero { try await Task.sleep(for: graceDelay) }
        }

        var seen = Set<String>()
        var records: [InboxRecord] = []
        var readable: [URL] = []
        for file in claimed {
            guard let data = try? Data(contentsOf: file) else {
                Self.log.error("Skipping unreadable inbox file \(file.lastPathComponent, privacy: .public)")
                continue
            }
            readable.append(file)
            for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
                guard let r = try? InboxRecord.decoder.decode(InboxRecord.self, from: Data(line)) else {
                    Self.log.warning("Skipping malformed inbox line (\(line.count) bytes)")
                    continue
                }
                if seen.insert(r.promptId).inserted { records.append(r) }
            }
        }
        return InboxBatch(records: records, files: readable)
    }

    /// Deletes the claimed files once their records are safely stored.
    public func commit(_ batch: InboxBatch) throws {
        for file in batch.files where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

public struct InboxBatch: Sendable {
    public let records: [InboxRecord]
    let files: [URL]
}
