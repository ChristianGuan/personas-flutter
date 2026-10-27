import Foundation

@main
struct PhotoPreparationTests {
    static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func main() {
        var replies = 0
        var cancelled = 0
        let pending = PhotoPreparation<Int>(requestID: 1) { request, value in
            replies += 1
            precondition(!request.pending)
            if case .success = value { preconditionFailure("Cancelled request succeeded") }
        }
        pending.operation.onCancel { cancelled += 1 }
        pending.cancel(photoError("cancel"))
        pending.cancel(photoError("cancel again"))
        precondition(!pending.finish(.success(42)))
        precondition(replies == 1 && cancelled == 1)

        var timedOut = false
        let stalled = PhotoPreparation<Int>(requestID: 2) { _, value in
            if case .failure = value { timedOut = true }
        }
        stalled.startTimeout(after: 0.01, error: photoError("timeout"))
        wait(0.05)
        precondition(timedOut && stalled.operation.cancelled && !stalled.pending)
        precondition(!stalled.finish(.success(2)))

        var successReplies = 0
        let success = PhotoPreparation<Int>(requestID: 3) { _, value in
            successReplies += 1
            precondition((try? value.get()) == 3)
        }
        success.startTimeout(after: 0.01, error: photoError("must not fire"))
        precondition(success.finish(.success(3)))
        wait(0.05)
        precondition(successReplies == 1 && !success.operation.cancelled)

        var batchReplies = 0
        let batch = PhotoPreparation<Int>(requestID: 4) { _, _ in batchReplies += 1 }
        batch.startTimeout(after: 0.01, error: photoError("old item timeout"))
        batch.startTimeout(after: 0.1, error: photoError("new item timeout"))
        wait(0.05)
        precondition(batch.pending && batchReplies == 0)
        precondition(batch.finish(.success(4)))

        var retryReplies = 0
        let retry = PhotoPreparation<Int>(requestID: 5) { _, _ in retryReplies += 1 }
        precondition(!pending.finish(.success(99)))
        precondition(retry.pending && retryReplies == 0)
        precondition(retry.finish(.success(5)))
        precondition(retryReplies == 1)
        print("PhotoPreparation: cancellation, timeout, late replies, retry and per-item deadline passed")
    }
}
