//
// Copyright (c) 2025-2026 PADL Software Pty Ltd
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

@OcaConnection
final class Ocp1MessageBatcher: Sendable {
  private typealias EncodedPDU = [UInt8]
  package typealias SendEncodedPDU = @Sendable (_: Data) async throws -> ()

  private let batchSize: OcaUint32
  private let dequeueInterval: Duration
  private let sendEncodedPdu: SendEncodedPDU

  private var encodedPdus = [EncodedPDU]()
  private var lastMessageType: OcaMessageType?

  private var periodicTask: Task<(), Error>?

  package init(
    batchSize: OcaUint32,
    dequeueInterval: Duration = .zero,
    sendEncodedPdu: @escaping SendEncodedPDU
  ) {
    self.batchSize = batchSize
    self.dequeueInterval = dequeueInterval
    self.sendEncodedPdu = sendEncodedPdu
  }

  var currentCount: Int {
    encodedPdus.count
  }

  var currentSize: Int {
    Ocp1Connection.MinimumPduSize + encodedPdus.reduce(0) { $0 + $1.count }
  }

  private func canCombine(type messageType: OcaMessageType) -> Bool {
    messageType != .ocaKeepAlive &&
      lastMessageType == messageType &&
      currentCount < Int(OcaUint16.max)
  }

  private func send(encodedPdus: [EncodedPDU], type messageType: OcaMessageType) async throws {
    let encodedPdu = try Ocp1Connection.encodeOcp1MessagePduData(
      type: messageType,
      encodedPdus: encodedPdus
    )

    try await sendEncodedPdu(Data(encodedPdu))
  }

  package func enqueue(_ message: Ocp1Message, type messageType: OcaMessageType) async throws {
    var encodedPdu = EncodedPDU()
    try (message as! _Ocp1MessageCodable).encode(type: messageType, into: &encodedPdu)

    // short-circuit, send immediately if batching is disabled
    guard dequeueInterval > .zero else {
      try await send(encodedPdus: [encodedPdu], type: messageType)
      return
    }

    let canCombine = canCombine(type: messageType) &&
      currentSize + encodedPdu.count <= Int(batchSize)
    // force immediate dequeing if we cannot combine this message
    if !canCombine { try await dequeue() }

    encodedPdus.append(encodedPdu)
    lastMessageType = messageType

    if encodedPdus.count == 1 {
      // if this is the first enqueued PDU, then start the periodic dequeue
      startPeriodicDequeue()
    }
  }

  private func startPeriodicDequeue() {
    guard periodicTask == nil else { return }

    let dequeueInterval = dequeueInterval

    periodicTask = Task { [weak self, dequeueInterval] in
      try await Task.sleep(for: dequeueInterval) // will check for cancellation
      try await self?.dequeue()
    }
  }

  private func stopPeriodicDequeue() {
    periodicTask?.cancel()
    periodicTask = nil
  }

  func dequeue() async throws {
    guard let lastMessageType, !encodedPdus.isEmpty else { return }

    let encodedPdus = encodedPdus
    self.encodedPdus.removeAll()
    self.lastMessageType = nil

    stopPeriodicDequeue()
    try await send(encodedPdus: encodedPdus, type: lastMessageType)
  }

  deinit {
    periodicTask?.cancel()
  }
}

extension Ocp1Connection {
  private func _getEffectiveBatchingOptions(
    _ batchingOptions: Ocp1ConnectionOptions
      .BatchingOptions
  ) -> (UInt32, Duration) {
    let batchSize = batchingOptions.batchSize ??
      (isDatagram ? OcaUint32(Ocp1MaximumDatagramPduSize) : OcaUint32(OcaUint16.max))
    var dequeueInterval = batchingOptions.batchThreshold ?? heartbeatTime / 100
    if dequeueInterval == .zero { dequeueInterval = .milliseconds(10) }
    return (batchSize, dequeueInterval)
  }

  func _configureBatching(_ batchingOptions: Ocp1ConnectionOptions.BatchingOptions?) {
    let batchSize: OcaUint32
    let dequeueInterval: Duration

    if let batchingOptions {
      (batchSize, dequeueInterval) = _getEffectiveBatchingOptions(batchingOptions)
    } else {
      batchSize = 1
      dequeueInterval = .zero
    }

    batcher = Ocp1MessageBatcher(
      batchSize: batchSize,
      dequeueInterval: dequeueInterval,
      sendEncodedPdu: sendMessagePduData
    )
  }
}
