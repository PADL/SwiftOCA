//
// Copyright (c) 2024-2025 PADL Software Pty Ltd
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
@_spi(SwiftOCAPrivate)
import SwiftOCA
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

public protocol OcaConnectionBroker: Actor {
  func connection(
    for objectPath: OcaOPath,
    type: (some OcaRoot).Type
  ) async throws -> Ocp1Connection

  func isOnline(_ objectPath: OcaOPath) async -> Bool

  func expire(connection aConnection: Ocp1Connection) async throws
}

actor _OcaDefaultConnectionBroker: OcaConnectionBroker {
  static let shared = _OcaDefaultConnectionBroker()

  private var connections = [OcaNetworkHostID: Ocp1Connection]()

  func connection<T: OcaRoot>(
    for objectPath: OcaOPath,
    type: T.Type
  ) async throws -> Ocp1Connection {
    if let connection = connections[objectPath.hostID] {
      return connection
    }

    let serviceNameOrID = try Ocp1Decoder()
      .decode(OcaString.self, from: Data(objectPath.hostID))

    // CM2: OcaNetworkHostID (deprecated)
    // CM3: ServiceID from OcaControlNetwork (let's asssume this is a hostname)
    // CM4: OcaControlNetwork ServiceName

    var addrInfo: UnsafeMutablePointer<addrinfo>?

    if getaddrinfo(serviceNameOrID, nil, nil, &addrInfo) < 0 {
      throw Ocp1Error.remoteDeviceResolutionFailed
    }

    defer {
      freeaddrinfo(addrInfo)
    }

    guard let firstAddr = addrInfo else {
      throw Ocp1Error.remoteDeviceResolutionFailed
    }

    for addr in sequence(first: firstAddr, next: { $0.pointee.ai_next }) {
      let connection: Ocp1Connection
      let data = Data(bytes: addr.pointee.ai_addr, count: Int(addr.pointee.ai_addrlen))
      let options = Ocp1ConnectionOptions(flags: [
        .retainObjectCacheAfterDisconnect,
        .automaticReconnect,
        .refreshSubscriptionsOnReconnection,
      ])

      switch addr.pointee.ai_socktype {
      case SwiftOCA.SOCK_STREAM:
        connection = try await Ocp1TCPConnection(deviceAddress: data, options: options)
      case SwiftOCA.SOCK_DGRAM:
        connection = try await Ocp1UDPConnection(deviceAddress: data, options: options)
      default:
        continue
      }

      try await connection.connect()

      connections[objectPath.hostID] = connection

      let classIdentification = try await connection
        .getClassIdentification(objectNumber: objectPath.oNo)
      guard classIdentification.isSubclass(of: T.classIdentification) else {
        throw Ocp1Error.status(.invalidRequest)
      }

      return connection
    }

    throw Ocp1Error.remoteDeviceResolutionFailed
  }

  func isOnline(_ objectPath: OcaOPath) async -> Bool {
    if let connection = connections[objectPath.hostID] {
      return await connection.isConnected
    }

    return false
  }

  func expire(connection aConnection: Ocp1Connection) async throws {
    for (hostID, connection) in connections {
      guard connection == aConnection else { continue }
      try await connection.disconnect()
      connections[hostID] = nil
    }
  }
}
