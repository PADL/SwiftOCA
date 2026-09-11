//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Synchronization

/// One timer for many deadlines on the continuous clock.
///
/// A timeout raced against an operation with its own `Task.sleep` is costly when the
/// operation usually wins, as a response does: cancelling the sleep resumes its task at
/// once, but the runtime keeps the timer, and with it the task's memory, until the
/// deadline passes. At thousands of requests a second that is hundreds of thousands of
/// parked timers, and as many late wake-ups. Here a cancelled wait is removed and
/// resumed at once, and a single loop sleeps until the earliest deadline. The loop stops
/// when it wakes to find nothing waiting, so it outlives the last wait by at most the
/// sleep it had already begun: stopping as each wait is cancelled would park a timer per
/// request again.
package final class DeadlineTimer: Sendable {
  typealias Instant = ContinuousClock.Instant
  private typealias Continuation = UnsafeContinuation<(), Error>

  private enum Wait {
    /// allocated; the waiter has not suspended yet
    case pending
    /// the waiter is suspended until the deadline
    case waiting(Instant, Continuation)
    /// cancelled before the waiter suspended
    case cancelled
  }

  /// The loop firing due waits: `generation` tells one that has been replaced to
  /// stop, and `wakesAt` is when it next wakes, unknown until its first pass.
  private struct Loop {
    let generation: UInt64
    var wakesAt: Instant?
    let task: Task<(), Never>
  }

  private struct State {
    var waits = [UInt64: Wait]()
    var nextID = UInt64(0)
    var loop: Loop?
    var generation = UInt64(0)
  }

  private let state = Mutex(State())

  package init() {}

  /// Runs `operation`, and if it hasn't returned within `duration`, calls `onTimeout` and
  /// throws `Ocp1Error.responseTimeout`; a zero duration means no timeout. The race is
  /// `withThrowingTimeout`'s, but its deadline is a wait on this timer, so an operation
  /// that wins, as a response or a read almost always does, leaves nothing behind.
  package func withThrowingTimeout<R: Sendable>(
    of duration: Duration,
    operation: @escaping @Sendable () async throws -> R,
    onTimeout: (@Sendable () async throws -> ())? = nil
  ) async throws -> R {
    try await _withThrowingTimeout(
      of: duration,
      clock: .continuous,
      operation: operation,
      onTimeout: onTimeout,
      sleepingUntil: { deadline in
        try await self.wait(until: deadline)
      }
    )
  }

  /// Returns at `deadline`, or throws `CancellationError` as soon as the calling task is
  /// cancelled.
  func wait(until deadline: Instant) async throws {
    let id = state.withLock { state in
      state.nextID &+= 1
      state.waits[state.nextID] = .pending
      return state.nextID
    }
    try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { (continuation: Continuation) in
        let outcome: Result<(), Error>? = state.withLock { state in
          if case .cancelled = state.waits[id] {
            state.waits[id] = nil
            return .failure(CancellationError())
          }
          guard deadline > .now else {
            state.waits[id] = nil
            return .success(())
          }
          state.waits[id] = .waiting(deadline, continuation)
          startLoop(unlessItWakesBy: deadline, &state)
          return nil
        }
        // resume outside the lock
        if let outcome {
          continuation.resume(with: outcome)
        }
      }
    } onCancel: {
      let continuation: Continuation? = state.withLock { state in
        switch state.waits[id] {
        case let .waiting(_, continuation):
          state.waits[id] = nil
          return continuation
        case .pending:
          state.waits[id] = .cancelled
          return nil
        case .cancelled, nil:
          return nil // already resolved
        }
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  /// The waits outstanding, so that a test can check nothing is left behind.
  var outstanding: Int {
    state.withLock { $0.waits.count }
  }

  /// Starts a loop if none is running, or replaces one that would wake after
  /// `deadline`, so that no wait fires late.
  private func startLoop(unlessItWakesBy deadline: Instant, _ state: inout State) {
    if let loop = state.loop {
      guard let wakesAt = loop.wakesAt, deadline < wakesAt else { return }
      loop.task.cancel()
    }
    state.generation &+= 1
    let generation = state.generation
    // Detached, because the loop serves every wait on the timer: it should take neither
    // the priority nor the task-local values of whichever waiter happened to start it.
    // It holds the timer only during each pass, never across its sleep, so a timer that
    // nothing uses any more is freed at once rather than kept alive by its own loop.
    let task = Task.detached(priority: .high) { [weak self] in
      while let pass = self?.pass(generation) {
        // resume outside the lock
        for continuation in pass.due {
          continuation.resume()
        }
        guard let next = pass.next else { return }
        do {
          try await Task.sleep(until: next, clock: .continuous)
        } catch {
          return // cancelled: replaced by a loop that wakes sooner
        }
      }
    }
    state.loop = Loop(generation: generation, wakesAt: nil, task: task)
  }

  /// One pass of loop `generation`: takes the waits that are due and finds when the next
  /// falls due, or ends the loop if nothing waits. `nil` if a loop that wakes sooner has
  /// replaced it.
  private func pass(_ generation: UInt64) -> (due: [Continuation], next: Instant?)? {
    state.withLock { state in
      guard state.loop?.generation == generation else {
        return nil
      }
      let now = Instant.now
      var due = [(id: UInt64, continuation: Continuation)]()
      var next: Instant?
      for (id, wait) in state.waits {
        guard case let .waiting(deadline, continuation) = wait else { continue }
        if deadline <= now {
          due.append((id, continuation))
        } else if next.map({ deadline < $0 }) ?? true {
          next = deadline
        }
      }
      // removed after iterating, as removing during it would copy the table
      for (id, _) in due {
        state.waits[id] = nil
      }
      if let next {
        state.loop?.wakesAt = next
      } else {
        state.loop = nil // nothing waits; the next wait starts a loop
      }
      return (due.map(\.continuation), next)
    }
  }
}
