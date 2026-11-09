import Foundation

/// Debounced, serial execution of one async job.
/// A trigger only ever cancels the *waiting* debounce, never work that is running:
/// triggers that arrive during a run are coalesced into exactly one follow-up run.
@MainActor
public final class SerialRunner {
    private let debounce: Duration
    private let work: @MainActor () async -> Void
    private var debounceTask: Task<Void, Never>?
    private var running = false
    private var rerunRequested = false

    public init(debounce: Duration = .milliseconds(300), work: @escaping @MainActor () async -> Void) {
        self.debounce = debounce
        self.work = work
    }

    public func trigger() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            self.requestRun()
        }
    }

    private func requestRun() {
        if running { rerunRequested = true; return }
        running = true
        // Unstructured on purpose: not a child of the cancellable debounce task.
        Task { [weak self] in
            guard let self else { return }
            repeat {
                self.rerunRequested = false
                await self.work()
            } while self.rerunRequested
            self.running = false
        }
    }
}
