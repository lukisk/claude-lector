import Foundation
import LectorCore

/// Calls `onChange` when the inbox directory changes, plus every 30 s as a safety net.
@MainActor
final class InboxWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private let runner: SerialRunner

    init(directory: URL, onChange: @escaping @MainActor () async -> Void) {
        self.runner = SerialRunner(work: onChange)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.trigger() } }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trigger() }
        }
        trigger()
    }

    /// Debounced and serial: a burst of file events (including the drain's own rename)
    /// never cancels a run in progress.
    func trigger() { runner.trigger() }
}
