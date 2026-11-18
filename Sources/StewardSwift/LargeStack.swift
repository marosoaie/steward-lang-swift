import Dispatch
import Foundation
import Synchronization

/// Runs work on a thread of its own with a large stack.
///
/// swift-syntax's parser recurses once per level of nesting, and on
/// macOS the threads that run `async` code, where a Dangerfile's rules run,
/// have 512 KiB stacks: deeply nested source, which a pull request
/// controls, would overflow one. The stack is reserved, not committed, so
/// only the depth that a parse reaches costs memory.
enum LargeStack {
    static let size = 64 << 20

    /// The value `work` returns, computed on a new thread with a `size`
    /// stack while the calling thread waits.
    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) -> Value {
        let slot = Slot<Value>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            slot.value.withLock { $0 = work() }
            done.signal()
        }
        thread.stackSize = size
        thread.start()
        done.wait()
        // The thread stores a value before it signals, so the fallback,
        // which would do the work on this thread, never runs.
        return slot.value.withLock { $0 } ?? work()
    }

    /// Where the thread leaves its value. A class, so that the thread and
    /// the caller share it; nothing else holds one.
    private final class Slot<Value: Sendable>: Sendable {
        let value = Mutex<Value?>(nil)
    }
}
