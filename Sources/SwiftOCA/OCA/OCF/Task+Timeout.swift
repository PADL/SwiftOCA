// https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/12

///
/// Execute an operation in the current task subject to a timeout.
///
/// - Parameters:
///   - seconds: The duration in seconds `operation` is allowed to run before timing out.
///   - operation: The async operation to perform.
/// - Returns: Returns the result of `operation` if it completed in time.
/// - Throws: Throws ``TimedOutError`` if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the
/// caller.
public func withThrowingTimeout<R: Sendable>(
    of duration: Duration,
    operation: @escaping @Sendable () async throws -> R
) async throws -> R {
    guard duration != .zero else {
        return try await operation()
    }

    return try await withThrowingTaskGroup(of: R.self) { group in
        let deadline = ContinuousClock.now + duration

        // Start actual work.
        group.addTask {
            try await operation()
        }
        // Start timeout child task.
        group.addTask {
            let interval = deadline - .now
            if interval > .zero {
                try await Task.sleep(for: duration)
            }
            try Task.checkCancellation()
            throw Ocp1Error.responseTimeout
        }
        // First finished child task wins, cancel the other task.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
