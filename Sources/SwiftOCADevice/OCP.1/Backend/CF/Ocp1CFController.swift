//
// Copyright (c) 2024 PADL Software Pty Ltd
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

#if canImport(CoreFoundation)

import AsyncAlgorithms
import AsyncExtensions
import CoreFoundation
import Foundation
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCA
import SystemPackage

protocol Ocp1CFControllerPrivate: Ocp1ControllerInternal,
  Ocp1ControllerInternalLightweightNotifyingInternal, Actor,
  Equatable, Hashable
{
  nonisolated var peerAddress: AnySocketAddress { get }

  func sendOcp1EncodedMessage(_ message: CFSocket.Message) async throws
}

extension Ocp1CFControllerPrivate {
  func sendOcp1EncodedData(
    _ data: Data,
    to destinationAddress: OcaNetworkAddress
  ) async throws {
    let networkAddress = try Ocp1NetworkAddress(networkAddress: destinationAddress)
    let peerAddress: SocketAddress = if networkAddress.address.isEmpty {
      // empty string means send to controller address but via UDP
      self.peerAddress
    } else {
      try AnySocketAddress(
        family: networkAddress.family,
        presentationAddress: networkAddress.presentationAddress
      )
    }
    try await sendOcp1EncodedMessage(CFSocket.Message(address: peerAddress, buffer: data))
  }

  nonisolated var identifier: String {
    (try? peerAddress.presentationAddress) ?? "unknown"
  }
}

actor Ocp1CFStreamController: Ocp1CFControllerPrivate, CustomStringConvertible {
  nonisolated let connectionPrefix: String

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  let peerAddress: AnySocketAddress
  var receiveMessageTask: Task<(), Never>?
  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.now
  var lastMessageSentTime = ContinuousClock.now
  weak var endpoint: Ocp1CFStreamDeviceEndpoint?

  var messages: AnyAsyncSequence<ControllerMessage> {
    _messages.eraseToAnyAsyncSequence()
  }

  private var _messages = AsyncThrowingChannel<ControllerMessage, Error>()
  private let socket: _CFSocketWrapper
  let notificationSocket: _CFSocketWrapper

  public nonisolated var description: String {
    "\(type(of: self))(socket: \(socket))"
  }

  init(
    endpoint: Ocp1CFStreamDeviceEndpoint,
    socket: _CFSocketWrapper,
    notificationSocket: _CFSocketWrapper
  ) async throws {
    self.socket = socket
    self.notificationSocket = notificationSocket
    peerAddress = socket.peerAddress!

    if peerAddress.family == AF_LOCAL {
      connectionPrefix = OcaLocalConnectionPrefix
    } else {
      connectionPrefix = OcaTcpConnectionPrefix
    }

    receiveMessageTask = Task { [self] in
      do {
        repeat {
          try await OcaDevice
            .receiveMessages { try await Array(socket.read(count: $0)) }
            .asyncForEach {
              await _messages.send($0)
            }
          if Task.isCancelled { break }
        } while true
      } catch {
        _messages.fail(error)
      }
    }
  }

  func close() async throws {
    // don't close the socket, it will be closed when last reference is released

    keepAliveTask?.cancel()
    keepAliveTask = nil

    receiveMessageTask?.cancel()
    receiveMessageTask = nil
  }

  func onConnectionBecomingStale() async throws {
    try await close()
  }

  var heartbeatTime = Duration.seconds(1) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    _ = try await socket.write(data: data)
  }

  func sendOcp1EncodedMessage(_ messagePdu: CFSocket.Message) async throws {
    try notificationSocket.send(data: messagePdu.1, to: messagePdu.0)
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

extension Ocp1CFStreamController: Equatable {
  public nonisolated static func == (
    lhs: Ocp1CFStreamController,
    rhs: Ocp1CFStreamController
  ) -> Bool {
    lhs.socket == rhs.socket
  }
}

extension Ocp1CFStreamController: Hashable {
  public nonisolated func hash(into hasher: inout Hasher) {
    socket.hash(into: &hasher)
  }
}

actor Ocp1CFDatagramController: Ocp1CFControllerPrivate, Ocp1ControllerDatagramSemantics {
  nonisolated var connectionPrefix: String { OcaUdpConnectionPrefix }

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  let peerAddress: AnySocketAddress
  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.now
  var lastMessageSentTime = ContinuousClock.now

  private(set) var isOpen: Bool = false
  weak var endpoint: Ocp1CFDatagramDeviceEndpoint?

  var messages: AnyAsyncSequence<ControllerMessage> {
    AsyncEmptySequence<ControllerMessage>().eraseToAnyAsyncSequence()
  }

  init(
    endpoint: Ocp1CFDatagramDeviceEndpoint,
    peerAddress: any SocketAddress
  ) async throws {
    self.endpoint = endpoint
    self.peerAddress = AnySocketAddress(peerAddress)
  }

  func onConnectionBecomingStale() async throws {
    await endpoint?.unlockAndRemove(controller: self)
  }

  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    try await sendOcp1EncodedMessage(CFSocket.Message(address: peerAddress, buffer: data))
  }

  func sendOcp1EncodedMessage(_ messagePdu: CFSocket.Message) async throws {
    try await endpoint?.sendOcp1EncodedMessage(messagePdu)
  }

  func close() async throws {}

  func didOpen() {
    isOpen = true
  }
}

extension Ocp1CFDatagramController: Equatable {
  public nonisolated static func == (
    lhs: Ocp1CFDatagramController,
    rhs: Ocp1CFDatagramController
  ) -> Bool {
    lhs.peerAddress == rhs.peerAddress
  }
}

extension Ocp1CFDatagramController: Hashable {
  public nonisolated func hash(into hasher: inout Hasher) {
    peerAddress.hash(into: &hasher)
  }
}

#endif
