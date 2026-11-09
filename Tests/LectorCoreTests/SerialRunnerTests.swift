import Foundation
import Testing
@testable import LectorCore

@MainActor
final class WorkLog {
    var started = 0
    var finished = 0
    var cancelledInside = 0
    var concurrent = 0
    var maxConcurrent = 0
}

@MainActor
@Test func triggerDuringRunDoesNotCancelRunningWork() async throws {
    let log = WorkLog()
    let runner = SerialRunner(debounce: .milliseconds(10)) {
        log.started += 1
        log.concurrent += 1
        log.maxConcurrent = max(log.maxConcurrent, log.concurrent)
        try? await Task.sleep(for: .milliseconds(200))
        if Task.isCancelled { log.cancelledInside += 1 }
        log.concurrent -= 1
        log.finished += 1
    }
    runner.trigger()
    try await Task.sleep(for: .milliseconds(60))   // work is running now
    runner.trigger()                               // e.g. the drain's own rename event
    runner.trigger()
    try await Task.sleep(for: .milliseconds(700))
    #expect(log.cancelledInside == 0)
    #expect(log.maxConcurrent == 1)
    #expect(log.started == 2)                      // one run + one coalesced follow-up
    #expect(log.finished == 2)
}

@MainActor
@Test func burstOfTriggersRunsOnce() async throws {
    let log = WorkLog()
    let runner = SerialRunner(debounce: .milliseconds(30)) { log.started += 1 }
    for _ in 0..<5 { runner.trigger() }
    try await Task.sleep(for: .milliseconds(200))
    #expect(log.started == 1)
}
