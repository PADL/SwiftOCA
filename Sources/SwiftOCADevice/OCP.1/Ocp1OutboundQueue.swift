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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA

/// Serialises everything a controller sends, so that no caller waits on the transport.
///
/// Command responses, notifications and keep-alives all reach the wire through
/// `sendMessages`, and every one of them used to await the write. A peer that stopped
/// reading therefore stalled its own command handling, the task that emitted an event,
/// and — because the device notifies controllers in turn — every other peer behind it.
///
/// One writer task drains one FIFO, so submission order is preserved: a response cannot
/// overtake a notification queued before it. That is why this is a queue and not a task
/// per write, which would reorder.
///
/// Entries are encoded bytes, not messages. Queueing `[Ocp1Message]` costs an array
/// allocation plus an existential box per message — Ocp1Notification1 is 64 bytes against
/// a 24-byte inline buffer — and keeps every parameter payload alive while it waits. One
/// encoded PDU is a single allocation and lets the message graph go. Coalescing, if it is
/// wanted later, can concatenate whole PDUs into one write on a stream transport without
/// retaining any of that.
package struct Ocp1OutboundQueue {
  /// Headroom for a peer that is briefly descheduled or whose window has just closed —
  /// jitter, not throughput. Depth cannot rescue a peer that is persistently slower than
  /// the notification rate; it only decides how long one looks healthy before we give up
  /// on it, so it is deliberately short. Override per endpoint if a deployment needs more.
  package static let defaultDepth = 256

  private let continuation: AsyncStream<Data>.Continuation
  private let task: Task<(), Never>

  package init(controller: some Ocp1ControllerInternal, depth: Int = Self.defaultDepth) {
    let (stream, continuation) = AsyncStream.makeStream(
      of: Data.self,
      // refuse the newest rather than evict a queued one: a dropped command response has
      // no recovery, and a gap in the middle of the stream is undetectable by the peer
      bufferingPolicy: .bufferingOldest(depth)
    )
    self.continuation = continuation
    task = Task { [weak controller] in
      for await data in stream {
        guard !Task.isCancelled, let controller else { break }
        do {
          try await controller.sendOcp1EncodedData(data)
        } catch {
          // the write failed, so the connection is finished; closing ends the read loop
          // and takes the controller through its normal teardown
          try? await controller.close()
          break
        }
      }
      continuation.finish()
    }
  }

  /// Queue `data` for transmission, or return `false` if the peer is too far behind.
  /// Never suspends.
  package func enqueue(_ data: Data) -> Bool {
    guard case .enqueued = continuation.yield(data) else { return false }
    return true
  }

  /// Stop writing and discard anything still queued. Whatever is left is destined for a
  /// transport that is going away, and flushing it would hold up teardown against the
  /// very peer that is not draining.
  package func cancel() {
    continuation.finish()
    task.cancel()
  }
}
