import Foundation

func photoError(_ message: String) -> NSError {
    NSError(domain: "Personas.Photos", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

final class PhotoOperation {
    private let lock = NSLock()
    private var stopped = false
    private var handlers: [() -> Void] = []
    var cancelled: Bool { lock.withLock { stopped } }
    func onCancel(_ handler: @escaping () -> Void) {
        let execute = lock.withLock { () -> Bool in
            if stopped { return true }; handlers.append(handler); return false
        }
        if execute { handler() }
    }
    func cancel() {
        let actions = lock.withLock { () -> [() -> Void] in stopped = true; let result = handlers; handlers = []; return result }
        actions.forEach { $0() }
    }
}

/// Owned by the main queue; cancellation does not wait for a provider callback.
final class PhotoPreparation<Value> {
    typealias Completion = (PhotoPreparation<Value>, Result<Value, Error>) -> Void
    let requestID: Int?
    let operation = PhotoOperation()
    private var completion: Completion?
    private var deadline: DispatchWorkItem?
    var pending: Bool { completion != nil }

    init(requestID: Int?, completion: @escaping Completion) {
        self.requestID = requestID
        self.completion = completion
    }

    func startTimeout(after seconds: TimeInterval, error: Error) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard pending else { return }
        deadline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.cancel(error) }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @discardableResult
    func finish(_ value: Result<Value, Error>) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let callback = takeCompletion() else { return false }
        callback(self, value)
        return true
    }

    func cancel(_ error: Error) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let callback = takeCompletion() else { return }
        operation.cancel()
        callback(self, .failure(error))
    }

    private func takeCompletion() -> Completion? {
        let callback = completion
        completion = nil
        deadline?.cancel()
        deadline = nil
        return callback
    }
}
