import Dispatch
import Foundation
@testable import StewardSwift
import Synchronization

/// A recursive walk as a rule might write one: swift-syntax's own
/// `SyntaxAnyVisitor`, which recurses once per level. A class, because
/// swift-syntax's visitors are.
final class NodeCounter: SyntaxAnyVisitor {
    private(set) var nodes = 0

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        nodes += 1
        return .visitChildren
    }

    static func count(_ tree: some SyntaxProtocol) -> Int {
        let counter = NodeCounter(viewMode: .sourceAccurate)
        counter.walk(tree)
        return counter.nodes
    }
}

extension LargeStack {
    /// `work`'s value, computed on a thread with the 512 KiB stack that
    /// `async` code gets on macOS.
    static func runOnSmallStack<Value: Sendable>(_ work: @escaping @Sendable () -> Value) -> Value? {
        let value = Mutex<Value?>(nil)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let result = work()
            value.withLock { $0 = result }
            done.signal()
        }
        thread.stackSize = 512 << 10
        thread.start()
        done.wait()
        return value.withLock { $0 }
    }
}
