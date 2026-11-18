import Dispatch
import Foundation
import Synchronization

/// Runs work on a thread of its own with a large stack, for as long as the
/// caller is willing to wait.
///
/// swift-syntax's parser recurses once per level of nesting, and on
/// macOS the threads that run `async` code, where a Dangerfile's rules run,
/// have 512 KiB stacks: deeply nested source, which a pull request
/// controls, would overflow one. The stack is reserved, not committed, so
/// only the depth that a parse reaches costs memory. It isn't larger,
/// since Linux can refuse a far larger reservation.
enum LargeStack {
    static let size = 64 << 20

    /// The value `work` returns, computed on a new thread with a `size`
    /// stack while the calling thread waits, or nil when it isn't done
    /// within `timeLimit`.
    ///
    /// Nothing can stop the thread, so work that runs out of time runs on
    /// until it ends or the process exits, and its value is dropped.
    /// `gate` counts it as a runaway meanwhile.
    static func run<Value: Sendable>(
        timeLimit: Duration? = nil,
        gate: ParseGate? = nil,
        _ work: @escaping @Sendable () -> Value
    ) -> Value? {
        let slot = Slot<Value>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let value = work()
            let wasAbandoned = slot.state.withLock { state in
                guard case .waiting = state else { return true }
                state = .finished(value)
                return false
            }
            if wasAbandoned {
                gate?.runawayEnded()
            }
            done.signal()
        }
        thread.stackSize = size
        thread.start()
        if let timeLimit {
            guard done.wait(timeout: .now() + dispatchInterval(timeLimit)) == .success else {
                // Under the slot's lock, so the thread can't end the runaway
                // before it starts.
                return slot.state.withLock { state in
                    if case .finished(let value) = state { return value }
                    state = .abandoned
                    gate?.runawayStarted()
                    return nil
                }
            }
        } else {
            done.wait()
        }
        return slot.state.withLock { state in
            guard case .finished(let value) = state else { return nil }
            return value
        }
    }

    /// `duration` in nanoseconds, between zero and about thirty years, so
    /// no duration can overflow the conversion.
    static func dispatchInterval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let wholeSeconds = Swift.min(Swift.max(seconds, 0), 1_000_000_000)
        let nanoseconds = Swift.max(attoseconds, 0) / 1_000_000_000
        return .nanoseconds(Int(wholeSeconds) * 1_000_000_000 + Int(nanoseconds))
    }

    /// Where the thread leaves its value, or learns that nobody waits for
    /// it. A class, so that the thread and the caller share it; nothing
    /// else holds one.
    private final class Slot<Value: Sendable>: Sendable {
        let state = Mutex<SlotState<Value>>(.waiting)
    }
}

/// What a `LargeStack` thread has done with its work.
private enum SlotState<Value: Sendable> {
    case waiting
    case finished(Value)
    case abandoned
}

/// The parses that ran out of time and still run. After one, no other
/// starts until it ends: a runaway parse holds a core and may keep
/// allocating, and a run should end soon after one.
///
/// A class, since every parse in the process shares one; tests make their
/// own.
final class ParseGate: Sendable {
    static let shared = ParseGate()

    private let runaways = Mutex(0)

    var isOpen: Bool {
        runaways.withLock { $0 <= 0 }
    }

    func runawayStarted() {
        runaways.withLock { $0 += 1 }
    }

    func runawayEnded() {
        runaways.withLock { $0 -= 1 }
    }
}
