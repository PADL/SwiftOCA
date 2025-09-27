// https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/12

public func withThrowingTimeout<R: Sendable, C: Clock>(
  of duration: C.Instant.Duration,
  tolerance: C.Instant.Duration? = nil,
  clock: C,
  operation: @escaping @Sendable () async throws -> R,
  onTimeout: (@Sendable () async throws -> ())? = nil
) async throws -> R {
  guard duration != .zero else {
    return try await operation()
  }

  return try await withThrowingTaskGroup(of: R.self) { group in
    let deadline = clock.now.advanced(by: duration)

    defer { group.cancelAll() }
    group.addTask {
      try await Task.sleep(until: deadline, tolerance: tolerance, clock: clock)
      try await onTimeout?()
      throw Ocp1Error.responseTimeout
    }
    group.addTask {
      try await operation()
    }

    return try await group.next()!
  }
}
