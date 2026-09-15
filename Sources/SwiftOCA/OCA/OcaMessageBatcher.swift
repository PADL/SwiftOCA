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

@OcaConnectionActor
final class OcaMessageBatcher: Sendable {
  package typealias SendEncodedPDU = @Sendable (_: Data) async throws -> ()

  private let batchSize: OcaUint32
  private let dequeueInterval: Duration
  private let sendEncodedPdu: SendEncodedPDU
  private let controlProtocol: OcaControlProtocol

  /// The batch, held as the PDU it will be sent as: messages are written straight
  /// into it, and `finishPdu` completes it when it is taken to be sent.
  private var pendingPdu = Data()
  private var pendingCount = 0
  private var lastMessageType: OcaMessageType?

  private var periodicTask: Task<(), Error>?
  private var periodicGeneration = 0

  package init(
    batchSize: OcaUint32,
    dequeueInterval: Duration = .zero,
    controlProtocol: OcaControlProtocol,
    sendEncodedPdu: @escaping SendEncodedPDU
  ) {
    self.batchSize = batchSize
    self.dequeueInterval = dequeueInterval
    self.controlProtocol = controlProtocol
    self.sendEncodedPdu = sendEncodedPdu
  }

  var currentCount: Int {
    pendingCount
  }

  var currentSize: Int {
    guard let lastMessageType else { return 0 }
    return controlProtocol.finishedPduSize(
      pendingPdu,
      messageCount: pendingCount,
      type: lastMessageType
    )
  }

  private func canCombine(type messageType: OcaMessageType) -> Bool {
    messageType != .ocaKeepAlive &&
      lastMessageType == messageType &&
      currentCount < Int(OcaUint16.max)
  }

  /// Detaches the batch and finishes its PDU, leaving the batch empty. The batcher
  /// holds the only reference to the PDU's storage, so finishing it does not copy.
  private func takePendingPdu() throws -> Data? {
    guard let lastMessageType, pendingCount > 0 else { return nil }

    var pdu = Data()
    swap(&pdu, &pendingPdu)
    let messageCount = pendingCount
    pendingCount = 0
    self.lastMessageType = nil

    try controlProtocol.finishPdu(&pdu, type: lastMessageType, messageCount: messageCount)
    return pdu
  }

  func enqueue(
    _ message: some _Ocp1MessageCodable,
    type messageType: OcaMessageType
  ) async throws {
    let message = try controlProtocol.prepareMessage(message, type: messageType)

    // short-circuit, send immediately if batching is disabled
    guard dequeueInterval > .zero else {
      var pdu = try controlProtocol.beginPdu(
        type: messageType,
        reservingCapacity: message.encodedSize
      )
      controlProtocol.appendMessage(message, to: &pdu, messageCount: 0)
      try controlProtocol.finishPdu(&pdu, type: messageType, messageCount: 1)
      try await sendEncodedPdu(pdu)
      return
    }

    let canCombine = canCombine(type: messageType) &&
      controlProtocol.finishedPduSize(
        pendingPdu,
        messageCount: pendingCount,
        type: messageType,
        adding: message.encodedSize
      ) <= Int(batchSize)

    if canCombine {
      controlProtocol.appendMessage(message, to: &pendingPdu, messageCount: pendingCount)
      pendingCount += 1
    } else {
      // Start the new batch before touching the pending one, so a message that
      // cannot begin a PDU leaves the pending batch intact.
      var pdu = try controlProtocol.beginPdu(
        type: messageType,
        reservingCapacity: message.encodedSize
      )
      controlProtocol.appendMessage(message, to: &pdu, messageCount: 0)

      // Detach the pending batch BEFORE the async send, then install the new
      // one. This prevents reentrancy issues where another enqueue() runs
      // during the send's await and corrupts the batch.
      let pendingPdu = try takePendingPdu()
      stopPeriodicDequeue()

      self.pendingPdu = pdu
      pendingCount = 1
      lastMessageType = messageType
      startPeriodicDequeue()

      // Now send the old batch (this may await and release the actor)
      if let pendingPdu {
        try await sendEncodedPdu(pendingPdu)
      }
    }
  }

  private func startPeriodicDequeue() {
    guard periodicTask == nil else { return }

    let dequeueInterval = dequeueInterval
    periodicGeneration &+= 1
    let generation = periodicGeneration

    periodicTask = Task { [weak self, dequeueInterval] in
      try await Task.sleep(for: dequeueInterval) // will check for cancellation
      try await self?.dequeue(timerGeneration: generation)
    }
  }

  private func stopPeriodicDequeue() {
    periodicTask?.cancel()
    periodicTask = nil
    // A timer already past its sleep cannot be cancelled; bump so it no longer matches and
    // cannot clear a successor's reference.
    periodicGeneration &+= 1
  }

  /// `timerGeneration` is set when called from `periodicTask` itself, which must not cancel the
  /// task it is running in: that would leave the send below running under cancellation. It
  /// clears only its own reference, and does so even when the batch turns out to be empty,
  /// otherwise `startPeriodicDequeue` would see a stale task and never arm another timer.
  func dequeue(timerGeneration: Int? = nil) async throws {
    if let timerGeneration {
      guard timerGeneration == periodicGeneration else { return }
      periodicTask = nil
    }

    guard let pdu = try takePendingPdu() else { return }

    if timerGeneration == nil {
      stopPeriodicDequeue()
    }
    try await sendEncodedPdu(pdu)
  }

  /// Discards work belonging to a transport generation that is being torn down.
  func cancelPending() {
    stopPeriodicDequeue()
    pendingPdu = Data()
    pendingCount = 0
    lastMessageType = nil
  }

  deinit {
    periodicTask?.cancel()
  }
}

extension OcaConnection {
  private func _getEffectiveBatchingOptions(
    _ batchingOptions: OcaConnectionOptions
      .BatchingOptions
  ) -> (UInt32, Duration) {
    let batchSize = batchingOptions.batchSize ??
      (isDatagram ? OcaUint32(Ocp1MaximumDatagramPduSize) : OcaUint32(OcaUint16.max))
    var dequeueInterval = batchingOptions.batchThreshold ?? effectiveHeartbeatTime / 100
    if dequeueInterval == .zero { dequeueInterval = .milliseconds(10) }
    return (batchSize, dequeueInterval)
  }

  func _configureBatching(_ batchingOptions: OcaConnectionOptions.BatchingOptions?) {
    let batchSize: OcaUint32
    let dequeueInterval: Duration

    if let batchingOptions {
      (batchSize, dequeueInterval) = _getEffectiveBatchingOptions(batchingOptions)
    } else {
      batchSize = 1
      dequeueInterval = .zero
    }

    batcher = OcaMessageBatcher(
      batchSize: batchSize,
      dequeueInterval: dequeueInterval,
      controlProtocol: controlProtocol,
      sendEncodedPdu: { [weak self] data in
        try await self?.sendMessagePduData(data)
      }
    )
  }
}
