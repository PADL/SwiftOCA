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

/// Serialises transport writes for one connection, in submission order.
package actor Ocp1WriteQueue {
  private var isBusy = false
  private var waiters = [UnsafeContinuation<Void, Never>]()
  private var head = 0

  package init() {}

  /// Writers waiting on the transport, excluding the one holding it.
  package var pending: Int {
    waiters.count - head
  }

  private func acquire() async {
    guard isBusy else {
      isBusy = true
      return
    }
    await withUnsafeContinuation { waiters.append($0) }
  }

  private func release() {
    guard head < waiters.count else {
      waiters.removeAll(keepingCapacity: true)
      head = 0
      isBusy = false
      return
    }
    let next = waiters[head]
    head += 1
    // Resumed waiters are left in place so a release is not O(n). Reclaim once they are half
    // the array: amortised O(1), and never more than half of it is dead. A queue that drains
    // resets `head` above, so this only runs under sustained backlog.
    if head * 2 >= waiters.count {
      waiters.removeFirst(head)
      head = 0
    }
    next.resume()
  }

  /// Runs `body` with exclusive, ordered access to the transport.
  ///
  /// Cancellation drops a PDU only before its first byte. Once a write has begun it runs to
  /// completion, because stream backends resume from an offset: aborting midway leaves a
  /// fragment on the wire and desyncs framing for every writer after it.
  package func serialised<T: Sendable>(
    _ body: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try await Task.detached { try await body() }.value
  }
}
