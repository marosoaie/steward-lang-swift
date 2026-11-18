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
/// only the depth that a parse reaches costs memory.
enum LargeStack {
    static let size = 64 << 20

    /// The value `work` returns, computed on a new thread with a `size`
    /// stack while the calling thread waits, or nil when it isn't done
    /// within `timeLimit`.
    ///
    /// Nothing can stop the thread, so work that runs out of time runs on
    /// until it ends or the process exits, and its value is dropped.
    static func run<Value: Sendable>(
        timeLimit: Duration? = nil,
        _ work: @escaping @Sendable () -> Value
    ) -> Value? {
        let slot = Slot<Value>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let value = work()
            slot.value.withLock { $0 = value }
            done.signal()
        }
        thread.stackSize = size
        thread.start()
        if let timeLimit {
            guard done.wait(timeout: .now() + dispatchInterval(timeLimit)) == .success else { return nil }
        } else {
            done.wait()
        }
        return slot.value.withLock { $0 }
    }

    /// `duration` in nanoseconds, between zero and about thirty years, so
    /// no duration can overflow the conversion.
    static func dispatchInterval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let wholeSeconds = Swift.min(Swift.max(seconds, 0), 1_000_000_000)
        let nanoseconds = Swift.max(attoseconds, 0) / 1_000_000_000
        return .nanoseconds(Int(wholeSeconds) * 1_000_000_000 + Int(nanoseconds))
    }

    /// Where the thread leaves its value. A class, so that the thread and
    /// the caller share it; nothing else holds one.
    private final class Slot<Value: Sendable>: Sendable {
        let value = Mutex<Value?>(nil)
    }
}
