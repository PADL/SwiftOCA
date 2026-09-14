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

#if canImport(IORing)

import AsyncAlgorithms
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

#if swift(>=6.0)
public import IORing
internal import IORingUtils
#else
public import IORing
@_implementationOnly import IORingUtils
#endif

import SocketAddress
import SwiftOCA
import Synchronization
import struct SystemPackage.Errno

protocol OcaIORingControllerPrivate: Ocp1ControllerInternal,
  Ocp1ControllerInternalLightweightNotifyingInternal, Actor,
  Equatable, Hashable
{
  nonisolated var peerAddress: AnySocketAddress { get }

  func sendOcp1EncodedMessage(_ message: Message) async throws
}

extension OcaIORingControllerPrivate {
  package func sendOcp1EncodedData(
    _ data: Data,
    to destinationAddress: OcaNetworkAddress
  ) async throws {
    let networkAddress = try Ocp1NetworkAddress(networkAddress: destinationAddress)
    let peerAddress: SocketAddress = if networkAddress.address.isEmpty {
      // empty string means send to controller address but via UDP
      self.peerAddress
    } else {
      try sockaddr_storage(
        family: networkAddress.family,
        presentationAddress: networkAddress.presentationAddress
      )
    }
    try await sendOcp1EncodedMessage(Message(address: peerAddress, buffer: [UInt8](data)))
  }
}

package actor OcaIORingStreamController: OcaIORingControllerPrivate, CustomStringConvertible {
  package nonisolated var flags: OcaControllerFlags {
    var flags: OcaControllerFlags = .supportsLocking
    if peerAddress.family == sa_family_t(AF_LOCAL) {
      flags.insert(.isLocal)
    }
    return flags
  }

  package nonisolated let connectionPrefix: String

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  let peerAddress: AnySocketAddress
  var receiveMessageTask: Task<(), Never>?
  package var keepAliveTask: Task<(), Error>?
  package let writeQueue: Ocp1WriteQueue? = Ocp1WriteQueue()
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package weak var endpoint: OcaIORingStreamDeviceEndpoint?
  package let controlProtocol: OcaControlProtocol

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  private let _messages = AsyncThrowingChannel<Ocp1MessageList, Error>()
  private let _socket: Mutex<Socket?>
  let notificationSocket: Socket

  package nonisolated var description: String {
    let socket = socket
    return "\(type(of: self))(socket: \(socket != nil ? String(describing: socket!) : "<disconnected>"))"
  }

  private nonisolated var socket: Socket? {
    _socket.withLock { $0 }
  }

  init(
    endpoint: OcaIORingStreamDeviceEndpoint,
    socket: Socket,
    notificationSocket: Socket
  ) async throws {
    _socket = .init(socket)
    self.notificationSocket = notificationSocket
    self.endpoint = endpoint
    controlProtocol = endpoint.controlProtocol

    peerAddress = try AnySocketAddress(socket.peerAddress)
    connectionPrefix = if peerAddress.family == AF_LOCAL {
      endpoint.controlProtocol.connectionPrefix(
        ocp1: OcaLocalConnectionPrefix,
        ocp2: OcaJsonLocalConnectionPrefix
      )
    } else {
      endpoint.controlProtocol.connectionPrefix(
        ocp1: OcaTcpConnectionPrefix,
        ocp2: OcaJsonTcpConnectionPrefix
      )
    }

    let controlProtocol = endpoint.controlProtocol
    let maximumPduSize = endpoint.maximumPduSize
    receiveMessageTask = Task { [weak self] in
      // one reader for the life of the connection: it buffers bytes between PDUs
      let reader = controlProtocol.makeReader(
        preservesPduBoundaries: false,
        maximumPduSize: maximumPduSize
      )
      do {
        repeat {
          guard !Task.isCancelled, let socket = self?.socket else { break }
          let messages = try await OcaDevice.asyncReceiveMessages(
            reader: reader,
            controlProtocol: controlProtocol,
            read: { try await Data(socket.read(count: $0, awaitingAllRead: $1)) }
          )
          guard let self else { return }
          await self._messages.send(messages)
        } while true
      } catch {
        self?._messages.fail(error)
      }
    }
  }

  private func _takeSocket() -> Socket? {
    _socket.withLock {
      let socket = $0
      $0 = nil
      return socket
    }
  }

  package func close() async {
    keepAliveTask?.cancel()
    keepAliveTask = nil

    // take and drop the socket reference so no new reads can start;
    // cancelling the receive task will cancel any pending io_uring read
    _ = _takeSocket()
    receiveMessageTask?.cancel()

    if let receiveMessageTask {
      _ = await receiveMessageTask.result
      self.receiveMessageTask = nil
    }

    _messages.finish()
  }

  deinit {
    receiveMessageTask?.cancel()
    keepAliveTask?.cancel()
    _messages.finish()
  }

  package var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    guard let socket else { throw Errno.badFileDescriptor }
    _ = try await socket.write(
      [UInt8](data),
      count: data.count,
      awaitingAllWritten: true
    )
  }

  func sendOcp1EncodedMessage(_ messagePdu: Message) async throws {
    try await notificationSocket.sendMessage(messagePdu)
  }

  package nonisolated var identifier: String {
    (try? peerAddress.presentationAddress) ?? "unknown"
  }
}

private extension Ocp1NetworkAddress {
  var presentationAddress: String {
    get throws {
      switch family {
      case sa_family_t(AF_INET):
        return "\(address):\(port)"
      case sa_family_t(AF_INET6):
        return "[\(address)]:\(port)"
      case sa_family_t(AF_LOCAL):
        return address
      default:
        throw Ocp1Error.status(.parameterError)
      }
    }
  }

  var family: sa_family_t {
    if address.hasPrefix("[") && address.contains("]") {
      sa_family_t(AF_INET6)
    } else if address.contains("/") {
      // presuming we have an absolute path to distinguish from IPv4 address
      sa_family_t(AF_LOCAL)
    } else {
      sa_family_t(AF_INET)
    }
  }
}

package actor OcaIORingDatagramController: OcaIORingControllerPrivate,
  Ocp1ControllerDatagramSemantics
{
  package nonisolated var flags: OcaControllerFlags {
    .supportsLocking
  }

  package nonisolated var connectionPrefix: String {
    controlProtocol.connectionPrefix(ocp1: OcaUdpConnectionPrefix, ocp2: OcaJsonUdpConnectionPrefix)
  }

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  let peerAddress: AnySocketAddress
  package var keepAliveTask: Task<(), Error>?
  package let writeQueue: Ocp1WriteQueue? = nil
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast

  package private(set) var isOpen: Bool = false
  package weak var endpoint: OcaIORingDatagramDeviceEndpoint?
  package let controlProtocol: OcaControlProtocol

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    AsyncEmptySequence<Ocp1MessageList>().eraseToAnyAsyncSequence()
  }

  init(
    endpoint: OcaIORingDatagramDeviceEndpoint,
    peerAddress: AnySocketAddress
  ) {
    self.endpoint = endpoint
    controlProtocol = endpoint.controlProtocol
    self.peerAddress = peerAddress
  }

  package var heartbeatTime = Duration.seconds(1) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    try await sendOcp1EncodedMessage(Message(address: peerAddress, buffer: [UInt8](data)))
  }

  func sendOcp1EncodedMessage(_ messagePdu: Message) async throws {
    try await endpoint?.sendOcp1EncodedMessage(messagePdu)
  }

  package nonisolated var identifier: String {
    (try? peerAddress.presentationAddress) ?? "unknown"
  }

  package func close() async throws {}

  package func didOpen() {
    isOpen = true
  }
}

extension OcaIORingControllerPrivate {
  package nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.peerAddress == rhs.peerAddress
  }
}

extension OcaIORingControllerPrivate {
  package nonisolated func hash(into hasher: inout Hasher) {
    peerAddress.hash(into: &hasher)
  }
}

#endif
