//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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
import Synchronization

// Connection monitor delivers responses keyed by request handle

extension Ocp1Connection {
  /// Monitor for matching requests and responses.
  /// Deliberately not isolated to `@OcaConnection` so that the
  /// receiveMessages/keepAlive loops run on the default executor and
  /// are not starved by work on other connections sharing the global actor.
  final class Monitor: Sendable, CustomStringConvertible {
    typealias Continuation = UnsafeContinuation<Ocp1Response, Error>

    /// A request is claimed before its command is written, because this class
    /// is not isolated to `@OcaConnection`: it decodes responses concurrently
    /// with the sender, so it can match one before the sender has suspended.
    /// Until then there is nowhere to deliver a result, so it is held in
    /// `completed` rather than dropped.
    private enum Request {
      /// claimed; the sender has not suspended yet
      case pending
      /// the sender is suspended awaiting a response
      case waiting(Continuation)
      /// a result arrived before the sender suspended
      case completed(Result<Ocp1Response, Error>)
    }

    /// The counter shares the requests lock so a handle can be allocated and
    /// claimed in one step, leaving no window in which it is merely reserved.
    private struct Requests {
      var entries = [OcaUint32: Request]()
      var count = UInt64(0)
    }

    private let _connection: Weak<Ocp1Connection>
    let _connectionID: Int
    private let _requests = Mutex<Requests>(Requests())
    private let _lastMessageReceivedTime = Mutex<ContinuousClock.Instant>(.now)

    /// Every request's response deadline on this connection: one timer, rather than a
    /// `Task.sleep` per request that outlives the request by the whole timeout.
    let deadlines = DeadlineTimer()

    init(_ connection: Ocp1Connection, id: Int) {
      _connection = Weak(connection)
      _connectionID = id
      updateLastMessageReceivedTime()
    }

    var connection: Ocp1Connection? {
      _connection.object
    }

    @concurrent
    func run() async throws {
      guard let connection else { throw Ocp1Error.notConnected }
      do {
        try await receiveMessages(connection)
      } catch Ocp1Error.notConnected {
        _resumeAllNotConnected()
      }
    }

    func stop() {
      _resumeAllNotConnected()
    }

    /// Zero is a legal handle on the wire, but it is `Ocp1Response.handle`'s
    /// default, so skip it: a zero-filled response must not match a request.
    private static func _allocateCommandHandle(_ requests: inout Requests) -> OcaUint32 {
      repeat {
        requests.count += 1
        let handle = OcaUint32(truncatingIfNeeded: requests.count)
        if handle != 0 {
          return handle
        }
      } while true
    }

    /// Allocates a handle and stamps it into `command`. An unmatched command
    /// records nothing, but still advances the counter `requestCount` reports.
    ///
    /// A recorded handle is allocated and claimed under one lock, so a response
    /// arriving before the sender suspends is kept rather than discarded, and
    /// handles still outstanding are skipped, which is what makes this total:
    /// the wire handle is 32 bits and is reissued after 2^32 requests.
    @discardableResult
    func allocateCommandHandle(
      _ command: inout Ocp1Command,
      responseRequired: Bool
    ) -> OcaUint32 {
      let handle = _requests.withLock { requests in
        repeat {
          let handle = Self._allocateCommandHandle(&requests)
          guard responseRequired else { return handle }
          if requests.entries[handle] == nil {
            requests.entries[handle] = .pending
            return handle
          }
        } while true
      }
      command.handle = handle
      return handle
    }

    /// Claims a specific `handle`, for tests that need to name one. Returns
    /// `false` if it is already outstanding.
    func claimCommandHandle(_ handle: OcaUint32) -> Bool {
      _requests.withLock { requests in
        guard requests.entries[handle] == nil else { return false }
        requests.entries[handle] = .pending
        return true
      }
    }

    /// Retires a claimed request, on whichever path the sender exits by. A
    /// `waiting` entry stays: its continuation is the only way to resume it.
    ///
    /// Keyed by handle alone: were a handle reissued between a sender
    /// completing and releasing, this would retire its successor.
    /// Reaching that needs 2^32 requests on one connection, so it is accepted.
    func releaseCommandHandle(_ handle: OcaUint32) {
      _requests.withLock { requests in
        if case .waiting = requests.entries[handle] {
          return
        }
        requests.entries.removeValue(forKey: handle)
      }
    }

    func response(for handle: OcaUint32) async throws -> Ocp1Response {
      // withUnsafeThrowingContinuation is not cancellation-aware, so without
      // this a cancelled sender would suspend on a continuation nobody resumes
      // and its enclosing task group would never drain. _complete handles
      // cancellation arriving before the suspension too, by parking the result.
      try await withTaskCancellationHandler {
        try await withUnsafeThrowingContinuation { continuation in
          let completed: Result<Ocp1Response, Error>? = _requests.withLock { requests in
            switch requests.entries[handle] {
            case .pending:
              requests.entries[handle] = .waiting(continuation)
              return nil
            case let .completed(result):
              requests.entries.removeValue(forKey: handle)
              return result
            case .waiting:
              // allocation makes this unreachable via sendCommandRrq; it catches
              // direct misuse, where overwriting would strand the first sender
              return .failure(Ocp1Error.invalidHandle)
            case nil:
              // the connection tore down between claiming and suspending
              return .failure(Ocp1Error.notConnected)
            }
          }
          // resume outside the lock
          if let completed {
            continuation.resume(with: completed)
          }
        }
      } onCancel: {
        _complete(handle: handle, with: .failure(CancellationError()))
      }
    }

    /// The one transition table. Returns a continuation to resume outside the
    /// lock, and whether `entry` was outstanding at all.
    private static func _apply(
      _ result: Result<Ocp1Response, Error>,
      to request: inout Request?
    ) -> (continuation: Continuation?, wasOutstanding: Bool) {
      switch request {
      case .pending:
        // hold the result until the sender suspends
        request = .completed(result)
        return (nil, true)
      case let .waiting(continuation):
        request = nil
        return (continuation, true)
      case .completed:
        // already resolved; first result wins, so a success is never displaced
        return (nil, true)
      case nil:
        return (nil, false)
      }
    }

    private func _resumeAllNotConnected() {
      let error = Ocp1Error.notConnected
      let continuations = _requests.withLock { requests in
        // snapshot the keys: the loop mutates the dictionary it iterates
        Array(requests.entries.keys).compactMap { handle in
          Self._apply(.failure(error), to: &requests.entries[handle]).continuation
        }
      }
      for continuation in continuations {
        continuation.resume(throwing: error)
      }
    }

    /// Completes a request whether or not its sender has suspended yet. Returns
    /// `false` if `handle` is not outstanding.
    @discardableResult
    private func _complete(
      handle: OcaUint32,
      with result: Result<Ocp1Response, Error>
    ) -> Bool {
      let (continuation, wasOutstanding) = _requests.withLock { requests in
        Self._apply(result, to: &requests.entries[handle])
      }
      // resume outside the lock
      continuation?.resume(with: result)
      return wasOutstanding
    }

    func resumeTimedOut(handle: OcaUint32) {
      _complete(handle: handle, with: .failure(Ocp1Error.responseTimeout))
    }

    func resume(with response: Ocp1Response) throws {
      guard _complete(handle: response.handle, with: .success(response)) else {
        throw Ocp1Error.invalidHandle
      }
    }

    /// Whether `handle`'s sender has suspended yet, so a test can wait for the
    /// state it means to exercise instead of sleeping and hoping.
    func isWaiting(handle: OcaUint32) -> Bool {
      _requests.withLock {
        if case .waiting = $0.entries[handle] {
          return true
        }
        return false
      }
    }

    func updateLastMessageReceivedTime() {
      _lastMessageReceivedTime.withLock { $0 = .now }
    }

    /// Requests issued on this connection generation; the monitor, and so the
    /// counter, is rebuilt on every reconnect.
    var requestCount: UInt64 {
      _requests.withLock { $0.count }
    }

    var outstandingRequests: [OcaUint32] {
      _requests.withLock { Array($0.entries.keys) }
    }

    var lastMessageReceivedTime: ContinuousClock.Instant {
      _lastMessageReceivedTime.withLock { $0 }
    }

    var description: String {
      "Ocp1Connection.Monitor[\(_connectionID)]"
    }
  }
}

extension Ocp1Connection.Monitor {
  private func receiveMessagePdu(
    _ connection: Ocp1Connection,
    reader: any OcaPduReader,
    source: ReadSource
  ) async throws -> (OcaMessageType, [Ocp1Message]) {
    let messagePduData: Data
    do {
      messagePduData = try await reader.nextPdu(read: source.read)
    } catch let error as Ocp1Error {
      switch error {
      case .pduTooShort, .invalidSyncValue, .invalidPduSize:
        connection.logger.warning("\(connection): dropping malformed PDU: \(error)")
      default:
        break
      }
      throw error
    }

    return try connection.controlProtocol.decodePdu(messagePduData)
  }

  /// The connection's read entry point, formed once per receive loop rather than per
  /// PDU: `connection.read` is a partial application of an actor-isolated method, so
  /// each mention of it allocates a closure.
  struct ReadSource {
    let read: (Int, Bool) async throws -> Data

    init(_ connection: Ocp1Connection) {
      read = connection.read(_:awaitingAllRead:)
    }
  }

  private func processMessage(
    _ connection: Ocp1Connection,
    _ message: Ocp1Message
  ) async throws {
    switch message {
    case is Ocp1Command:
      connection.logger.warning("device sent unexpected command \(message); ignoring")
    case let notification as Ocp1Notification1:
      if notification.parameters.parameterCount == 2 {
        await connection.notifySubscribers(
          of: notification.parameters.eventData.event,
          with: notification.parameters.eventData.eventParameters
        )
      }
    case let response as Ocp1Response:
      try resume(with: response)
    case is Ocp1KeepAlive1:
      fallthrough
    case is Ocp1KeepAlive2:
      break
    case let notification as Ocp1Notification2:
      try notification.throwIfException()
      await connection.notifySubscribers(of: notification.event, with: notification.data)
    default:
      throw Ocp1Error.unknownPduType
    }
  }

  private func onDatagramConnectionOpen(_ connection: Ocp1Connection) async {
    let (isDatagram, isConnecting) = await (connection.isDatagram, connection.isConnecting)
    if isDatagram, isConnecting {
      await connection.onConnectionOpen()
    }
  }

  private func receiveMessage(
    _ connection: Ocp1Connection,
    reader: any OcaPduReader,
    source: ReadSource
  ) async throws {
    let (_, messages) = try await receiveMessagePdu(
      connection,
      reader: reader,
      source: source
    )

    updateLastMessageReceivedTime()
    await onDatagramConnectionOpen(connection)

    for message in messages {
      do {
        try await processMessage(connection, message)
      } catch {
        // processMessage does no I/O, so nothing it throws says anything about
        // the health of the connection: a response nobody is waiting for, an
        // unknown PDU type, an event delivered as an exception. Drop the one
        // message — the siblings sharing this batched PDU have senders of
        // their own still waiting, and the connection is fine.
        connection.logger.debug("dropping \(message): \(error)")
      }
    }
  }

  private func keepAlive(_ connection: Ocp1Connection) async throws {
    let heartbeatTime = await connection.effectiveHeartbeatTime
    let keepAliveThreshold = heartbeatTime * 3

    repeat {
      let now = ContinuousClock.now

      if now - lastMessageReceivedTime >= keepAliveThreshold {
        connection.logger
          .info(
            "\(connection): no heartbeat packet received in past \(keepAliveThreshold)"
          )
        throw Ocp1Error.missingKeepalive
      }

      let lastMessageSentTime = await connection.lastMessageSentTime
      let timeSinceLastMessageSent = now - lastMessageSentTime
      var sleepTime = heartbeatTime
      if timeSinceLastMessageSent >= heartbeatTime {
        try await connection.sendKeepAlive()
      } else {
        sleepTime -= timeSinceLastMessageSent
      }
      try await Task.sleep(for: sleepTime)
    } while true
  }

  @concurrent
  func receiveMessages(_ connection: Ocp1Connection) async throws {
    let heartbeatTime = await connection.effectiveHeartbeatTime
    let controlProtocol = connection.controlProtocol
    // `isMessageOriented` describes writes (whole PDUs per send, so the write queue
    // can be bypassed); a stream that takes whole PDUs on send may still deliver
    // coalesced or partial ones on receive. Only a datagram guarantees one PDU per
    // read, so that is what the reader is given.
    let (isDatagram, maximumPduSize) = await (
      connection.isDatagram,
      connection.options.maximumPduSize
    )

    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { [weak self] in
          // one reader per receive loop: it buffers bytes between PDUs
          let reader = controlProtocol.makeReader(
            isMessageOriented: isDatagram,
            maximumPduSize: maximumPduSize
          )
          let source = ReadSource(connection)
          repeat {
            try Task.checkCancellation()
            guard let self else { return }
            try await receiveMessage(connection, reader: reader, source: source)
          } while true
        }
        if heartbeatTime > .zero {
          group.addTask { [weak self] in
            try await self?.keepAlive(connection)
          }
        }
        try await group.next()
        group.cancelAll()
      }
    } catch {
      // if we're not already in the middle of connecting or re-connecting,
      // possibly trigger a reconnect depending on the autoReconnect policy
      // and the nature of the error
      let isConnecting = await connection.isConnecting
      if !isConnecting {
        try? await connection.onMonitorError(id: _connectionID, error)
      }
      throw error
    }
  }
}
