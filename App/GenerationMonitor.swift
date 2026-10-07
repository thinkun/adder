import Foundation
import Dispatch

/// Controls acceptance of generation results, not native SDK execution.
/// A synchronous SDK wait remains occupied after timeout. Never reuse its model
/// or call cleanup from another thread until that worker has actually returned.
final class GenerationMonitor: @unchecked Sendable {
    struct Ticket: Equatable, Sendable { let id: UUID }
    enum Status: Equatable, Sendable { case running, timedOut, tokenLimit, cancelled, completed }
    enum TokenDecision: Equatable, Sendable { case accepted, timedOut, tokenLimit, cancelled, stale }
    struct Snapshot: Sendable {
        let ticket: Ticket
        let status: Status
        let generatedTokens: Int
        let workerPending: Bool
        let elapsedSeconds: TimeInterval
        let idleSeconds: TimeInterval
    }
    enum MonitorError: LocalizedError {
        case workerStillPending
        var errorDescription: String? {
            "The previous local generation is still running. Your capture is retained. Wait for it to return, or restart the app if it remains stuck."
        }
    }
    private struct State {
        let ticket: Ticket
        let deadline: UInt64
        let started: UInt64
        let idleLimit: UInt64
        var lastProgress: UInt64
        let tokenLimit: Int
        var count = 0
        var status = Status.running
        var workerPending = true
    }
    private let lock = NSLock()
    private let uptime: @Sendable () -> UInt64
    private var state: State?

    init(uptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        uptime = uptimeNanoseconds
    }

    func begin(timeoutSeconds: TimeInterval = 90, idleTimeoutSeconds: TimeInterval = 30, tokenLimit: Int = 1600) throws -> Ticket {
        lock.lock(); defer { lock.unlock() }
        guard state?.workerPending != true else { throw MonitorError.workerStillPending }
        let ticket = Ticket(id: UUID())
        let seconds = timeoutSeconds.isFinite ? max(0, min(timeoutSeconds, 86400)) : 90
        let started = uptime()
        let deadline = started &+ UInt64(seconds * 1_000_000_000)
        let idleSeconds = idleTimeoutSeconds.isFinite ? max(0, min(idleTimeoutSeconds, 86400)) : 30
        state = State(ticket: ticket, deadline: deadline, started: started,
                      idleLimit: UInt64(idleSeconds * 1_000_000_000), lastProgress: started,
                      tokenLimit: max(1, tokenLimit))
        return ticket
    }

    /// Called by an independent timer/task, never through the blocked model actor.
    /// Returns true only for the transition to timeout, so the UI reports it once.
    @discardableResult
    func expireIfNeeded(_ ticket: Ticket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var current = state, current.ticket == ticket, current.status == .running,
              hasExpired(current, at: uptime()) else { return false }
        current.status = .timedOut
        state = current
        return true
    }

    /// Called after a token arrives. This check cannot interrupt a wait already
    /// inside the SDK; use expireIfNeeded on an independent watchdog as well.
    func recordToken(_ ticket: Ticket, generatedTokens: Int? = nil) -> TokenDecision {
        lock.lock(); defer { lock.unlock() }
        guard var current = state, current.ticket == ticket, current.workerPending else { return .stale }
        if current.status == .timedOut { return .timedOut }
        if current.status == .tokenLimit { return .tokenLimit }
        if current.status == .cancelled { return .cancelled }
        guard current.status == .running else { return .stale }
        let now = uptime()
        if hasExpired(current, at: now) {
            current.status = .timedOut; state = current; return .timedOut
        }
        current.count = max(current.count + 1, generatedTokens ?? 0)
        current.lastProgress = now
        if current.count > current.tokenLimit {
            current.status = .tokenLimit; state = current; return .tokenLimit
        }
        state = current
        return .accepted
    }

    /// Call only after the native worker and its serial cleanup have returned.
    /// False means any draft/error from this worker is stale and must not replace UI state.
    @discardableResult
    func finish(_ ticket: Ticket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var current = state, current.ticket == ticket, current.workerPending else { return false }
        if current.status == .running, hasExpired(current, at: uptime()) { current.status = .timedOut }
        let accept = current.status == .running
        current.workerPending = false
        if accept { current.status = .completed }
        state = current
        return accept
    }

    var snapshot: Snapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let state else { return nil }
        let now = uptime()
        return Snapshot(ticket: state.ticket, status: state.status, generatedTokens: state.count,
                        workerPending: state.workerPending,
                        elapsedSeconds: Double(now - state.started) / 1_000_000_000,
                        idleSeconds: Double(now - state.lastProgress) / 1_000_000_000)
    }

    var canStartGeneration: Bool {
        lock.lock(); defer { lock.unlock() }
        return state?.workerPending != true
    }

    /// Invalidates publication immediately; does not cancel native SDK execution.
    @discardableResult
    func cancel(_ ticket: Ticket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var current = state, current.ticket == ticket, current.status == .running else { return false }
        current.status = .cancelled; state = current; return true
    }

    func shouldContinue(_ ticket: Ticket) -> Bool {
        _ = expireIfNeeded(ticket)
        lock.lock(); defer { lock.unlock() }
        return state?.ticket == ticket && state?.status == .running && state?.workerPending == true
    }

    private func hasExpired(_ state: State, at now: UInt64) -> Bool {
        now >= state.deadline || (state.count > 0 && now - state.lastProgress >= state.idleLimit)
    }
}
