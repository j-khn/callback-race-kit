import Foundation
import XCTest
import CallbackRaceKit

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    func set() {
        lock.lock()
        stored = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

final class CallbackBridgeTests: XCTestCase {
    func testSynchronousCompletionAndDuplicateCallbackUseFirstResult() async throws {
        let value = try await CallbackBridge.run { finish in
            finish(.success("first"))
            finish(.success("second"))
            return nil
        }
        XCTAssertEqual(value, "first")
    }

    func testAlreadyCancelledTaskSkipsRegistration() async {
        let started = LockedFlag()
        let task = Task<String, any Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CallbackBridge.run { _ in
                started.set()
                return nil
            }
        }
        let result = await task.result
        guard case .failure(let error) = result else {
            return XCTFail("Expected cancellation")
        }
        XCTAssertTrue(error is CancellationError)
        XCTAssertFalse(started.value)
    }

    func testCancellationIsForwardedToLegacyToken() async {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        let task = Task<String, any Error> {
            try await CallbackBridge.run { _ in
                startedContinuation.yield(())
                return CancellationToken {
                    cancelledContinuation.yield(())
                }
            }
        }

        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()
        task.cancel()

        let result = await task.result
        guard case .failure(let error) = result else {
            return XCTFail("Expected cancellation")
        }
        XCTAssertTrue(error is CancellationError)

        var cancelledIterator = cancelled.makeAsyncIterator()
        let cancellationSignal = await cancelledIterator.next()
        XCTAssertNotNil(cancellationSignal)
    }
}
