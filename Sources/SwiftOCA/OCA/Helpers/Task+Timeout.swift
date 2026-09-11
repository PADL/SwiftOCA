// https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/12

public func withThrowingTimeout<R: Sendable, C: Clock>(
  of duration: C.Instant.Duration,
  tolerance: C.Instant.Duration? = nil,
  clock: C,
  operation: @escaping @Sendable () async throws -> R,
  onTimeout: (@Sendable () async throws -> ())? = nil
) async throws -> R {
  try await _withThrowingTimeout(
    of: duration,
    clock: clock,
    operation: operation,
    onTimeout: onTimeout,
    sleepingUntil: { deadline in
      try await Task.sleep(until: deadline, tolerance: tolerance, clock: clock)
    }
  )
}

/// `withThrowingTimeout` with the wait for the deadline supplied: `sleepingUntil` must
/// return at the deadline, or throw once its task is cancelled. A caller that races many
/// operations it expects to win can pass a shared `DeadlineTimer`, because the
/// `Task.sleep` of a timeout that loses is kept by the runtime, with its task, until the
/// deadline passes.
func _withThrowingTimeout<R: Sendable, C: Clock>(
  of duration: C.Instant.Duration,
  clock: C,
  operation: @escaping @Sendable () async throws -> R,
  onTimeout: (@Sendable () async throws -> ())?,
  sleepingUntil: @escaping @Sendable (C.Instant) async throws -> ()
) async throws -> R {
  guard duration != .zero else {
    return try await operation()
  }

  return try await withThrowingTaskGroup(of: R.self) { group in
    let deadline = clock.now.advanced(by: duration)

    defer { group.cancelAll() }
    group.addTask {
      try await sleepingUntil(deadline)
      try? await onTimeout?()
      throw Ocp1Error.responseTimeout
    }
    group.addTask {
      try await operation()
    }

    return try await group.next()!
  }
}
