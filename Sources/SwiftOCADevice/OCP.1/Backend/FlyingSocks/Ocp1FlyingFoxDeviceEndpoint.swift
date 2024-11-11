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

#if os(macOS) || os(iOS)

import AsyncExtensions
import FlyingFox
import FlyingSocks
import Foundation
import Logging
import SwiftOCA

@OcaDevice
public final class Ocp1FlyingFoxDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  typealias ControllerType = Ocp1FlyingFoxController

  public var controllers: [OcaController] {
    _controllers
  }

  let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1FlyingFoxDeviceEndpoint")
  let timeout: Duration
  let device: OcaDevice

  private var httpServer: HTTPServer!
  private let address: sockaddr_storage
  private var _controllers = [Ocp1FlyingFoxController]()
  #if canImport(dnssd)
  private var endpointRegistrationHandle: OcaDeviceEndpointRegistrar.Handle?
  #endif

  final class Handler: WSMessageHandler, @unchecked
  Sendable {
    weak var endpoint: Ocp1FlyingFoxDeviceEndpoint?

    init(_ endpoint: Ocp1FlyingFoxDeviceEndpoint) {
      self.endpoint = endpoint
    }

    func makeMessages(for client: AsyncStream<WSMessage>) async throws
      -> AsyncStream<WSMessage>
    {
      AsyncStream<WSMessage> { continuation in
        let controller = Ocp1FlyingFoxController(
          endpoint: endpoint,
          inputStream: client,
          outputStream: continuation
        )

        let task = Task { @OcaDevice in
          if let endpoint {
            await controller.handle(for: endpoint)
          }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
      }
    }
  }

  public convenience init(
    address: Data,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    var storage = sockaddr_storage()
    _ = withUnsafeMutableBytes(of: &storage) { dst in
      address.withUnsafeBytes { src in
        memcpy(dst.baseAddress!, src.baseAddress!, src.count)
      }
    }
    try await self.init(address: storage, timeout: timeout, device: device)
  }

  public convenience init(
    path: String,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    let address = sockaddr_un.unix(path: path).makeStorage()
    try await self.init(address: address, timeout: timeout, device: device)
  }

  private init(
    address: sockaddr_storage,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    self.device = device
    self.address = address
    self.timeout = timeout

    // FIXME: API impedance mismatch
    let address: FlyingSocks.SocketAddress

    switch self.address.ss_family {
    case sa_family_t(AF_INET):
      address = try sockaddr_in.make(from: self.address)
    case sa_family_t(AF_INET6):
      address = try sockaddr_in6.make(from: self.address)
    case sa_family_t(AF_LOCAL):
      address = try sockaddr_un.make(from: self.address)
    default:
      throw Ocp1Error.unknownServiceType
    }

    httpServer = HTTPServer(
      address: address,
      timeout: timeout.timeInterval
    )

    await httpServer.appendRoute("GET /", to: .webSocket(Handler(self)))

    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    withUnsafePointer(to: address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        let presentationAddress = deviceAddressToString(sa)
        return "\(type(of: self))(address: \(presentationAddress), timeout: \(timeout))"
      }
    }
  }

  public func run() async throws {
    do {
      if port != 0 {
        #if canImport(dnssd)
        Task { endpointRegistrationHandle = try await OcaDeviceEndpointRegistrar.shared
          .register(endpoint: self, device: device)
        }
        #endif
      }
      try await httpServer.run()
    } catch {
      throw error
    }
  }

  public nonisolated var serviceType: OcaDeviceEndpointRegistrar.ServiceType {
    .tcpWebSocket
  }

  public nonisolated var port: UInt16 {
    var address = address
    return UInt16(bigEndian: withUnsafePointer(to: &address) { address in
      switch Int32(address.pointee.ss_family) {
      case AF_INET:
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
          sin.pointee.sin_port
        }
      case AF_INET6:
        address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
          sin6.pointee.sin6_port
        }
      default:
        0
      }
    })
  }

  func add(controller: Ocp1FlyingFoxController) async {
    _controllers.append(controller)
  }

  func remove(controller: Ocp1FlyingFoxController) async {
    _controllers.removeAll(where: { $0.id == controller.id })
  }
}
#endif
