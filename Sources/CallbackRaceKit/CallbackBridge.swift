import Foundation

public struct CancellationToken: Sendable {
    private let cancelBody: @Sendable () -> Void

    public init(_ cancel: @escaping @Sendable () -> Void) {
        cancelBody = cancel
    }

    public func cancel() {
        cancelBody()
    }
}

public enum CallbackBridge {
    /// Bridges a one-shot callback API into async/await.
    ///
    /// The first completion or task cancellation wins. Late and duplicate
    /// callbacks are ignored. Cancellation is forwarded when the legacy API
    /// supplies a token; the legacy operation may still finish if it is not
    /// cooperatively cancellable.
    public static func run<Value: Sendable>(
        start: @escaping @Sendable (
            @escaping @Sendable (Result<Value, any Error>) -> Void
        ) -> CancellationToken?
    ) async throws -> Value {
        let state = BridgeState<Value>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard state.install(continuation), state.beginRegistration() else {
                    return
                }

                let token = start { result in
                    state.complete(result)
                }
                state.attach(token)
            }
        } onCancel: {
            state.cancel()
        }
    }
}

private final class BridgeState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var token: CancellationToken?
    private var resolved = false
    private var cancelled = false

    func install(_ continuation: CheckedContinuation<Value, any Error>) -> Bool {
        lock.lock()
        if resolved {
            let shouldResume = cancelled
            lock.unlock()
            if shouldResume {
                continuation.resume(throwing: CancellationError())
            }
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func beginRegistration() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !resolved
    }

    func attach(_ token: CancellationToken?) {
        guard let token else { return }
        lock.lock()
        let cancelImmediately = resolved && cancelled
        if !resolved {
            self.token = token
        }
        lock.unlock()
        if cancelImmediately {
            token.cancel()
        }
    }

    func complete(_ result: Result<Value, any Error>) {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return
        }
        resolved = true
        let continuation = self.continuation
        self.continuation = nil
        token = nil
        lock.unlock()

        guard let continuation else { return }
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func cancel() {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return
        }
        resolved = true
        cancelled = true
        let continuation = self.continuation
        let token = self.token
        self.continuation = nil
        self.token = nil
        lock.unlock()

        token?.cancel()
        continuation?.resume(throwing: CancellationError())
    }
}
