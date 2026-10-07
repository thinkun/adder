import Foundation

private final class FakeUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance(seconds: UInt64) { lock.lock(); defer { lock.unlock() }; value += seconds * 1_000_000_000 }
}

@main struct GenerationMonitorChecks {
    static func main() throws {
        let clock = FakeUptime()
        let monitor = GenerationMonitor(uptimeNanoseconds: { clock.read() })
        let ticket = try monitor.begin(timeoutSeconds: 10, tokenLimit: 2)
        precondition(monitor.recordToken(ticket) == .accepted)
        // The native worker seam is intentionally pending: no completion occurs.
        clock.advance(seconds: 10)
        precondition(monitor.expireIfNeeded(ticket), "Watchdog must work while no token arrives")
        precondition(monitor.snapshot?.workerPending == true, "Timeout must not pretend to cancel the native worker")
        precondition(monitor.snapshot?.status == .timedOut)
        precondition(!monitor.expireIfNeeded(ticket), "Report timeout only once")
        var refused = false
        do { _ = try monitor.begin() } catch { refused = true }
        precondition(refused, "Never reuse a model while its old wait remains pending")
        precondition(!monitor.finish(ticket), "Late completion must not publish a stale draft")
        precondition(monitor.snapshot?.workerPending == false, "Worker becomes reusable only after it returns")

        let fresh = try monitor.begin(timeoutSeconds: 10, tokenLimit: 2)
        precondition(!monitor.finish(ticket), "An old completion cannot terminate a newer generation")
        precondition(monitor.snapshot?.ticket == fresh && monitor.snapshot?.workerPending == true)
        precondition(monitor.recordToken(fresh) == .accepted)
        precondition(monitor.recordToken(fresh) == .accepted)
        precondition(monitor.recordToken(fresh) == .tokenLimit)
        precondition(!monitor.finish(fresh), "Over-budget output must not publish")

        let success = try monitor.begin(timeoutSeconds: 5)
        precondition(monitor.recordToken(success, generatedTokens: 30) == .accepted)
        precondition(monitor.snapshot?.generatedTokens == 30)
        precondition(monitor.finish(success), "Timely completion can publish")
        precondition(!monitor.finish(success), "Completion cannot publish twice")

        let noWatchdogTick = try monitor.begin(timeoutSeconds: 1)
        clock.advance(seconds: 2)
        precondition(!monitor.finish(noWatchdogTick), "Finish itself must enforce deadline even if timer was delayed")

        let prefill = try monitor.begin(timeoutSeconds: 90, idleTimeoutSeconds: 30)
        clock.advance(seconds: 40)
        precondition(monitor.shouldContinue(prefill), "First-token prefill uses total timeout, not token-stall timeout")
        precondition(monitor.recordToken(prefill) == .accepted)
        clock.advance(seconds: 30)
        precondition(monitor.expireIfNeeded(prefill), "Idle watchdog expires a stalled stream after first token")
        precondition(monitor.snapshot?.elapsedSeconds == 70)
        precondition(monitor.snapshot?.idleSeconds == 30)
        precondition(!monitor.finish(prefill))

        let cancelled = try monitor.begin()
        precondition(monitor.cancel(cancelled))
        precondition(!monitor.shouldContinue(cancelled))
        precondition(!monitor.canStartGeneration, "Cancel must preserve pending worker exclusion")
        precondition(monitor.recordToken(cancelled) == .cancelled)
        precondition(!monitor.finish(cancelled), "Cancelled completion must not publish")
        precondition(monitor.canStartGeneration, "Only finished worker restores model availability")
        print("Passed: blocked-wait watchdog seam, pending-worker exclusion, stale completion, token budget, monotonic deadline. No SDK execution or cancellation claimed.")
    }
}
