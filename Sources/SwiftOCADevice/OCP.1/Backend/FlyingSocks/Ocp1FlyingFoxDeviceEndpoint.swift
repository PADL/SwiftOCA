//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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

#if canImport(FlyingFox)

import AsyncExtensions
import FlyingFox
import FlyingSocks
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import SwiftOCA
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif

@OcaDevice
public final class Ocp1FlyingFoxDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  package typealias ControllerType = Ocp1FlyingFoxController

  public var controllers: [OcaController] {
    _controllers
  }

  package let timeout: Duration
  package let device: OcaDevice
  package let logger: Logger
  /// The HTTP path each control protocol is served on, advertised as its service's `path`
  /// TXT record when it is not `/` (AES70-4 Table 5). Protocols sharing a path are told
  /// apart by the WebSocket subprotocol the client offers.
  public nonisolated let paths: [OcaControlProtocol: String]
  package nonisolated(unsafe) var enableMessageTracing = false

  private(set) var httpServer: HTTPServer!
  private let address: sockaddr_storage
  private var _controllers = [Ocp1FlyingFoxController]()
  #if canImport(dnssd)
  private var _endpointRegistrarTask: Task<(), Error>?
  #endif

  final class Handler: WSMessageHandler, @unchecked
  Sendable {
    package weak var endpoint: Ocp1FlyingFoxDeviceEndpoint?
    /// the peer the WebSocket upgrade came from, for logging
    private let identifier: String
    package let controlProtocol: OcaControlProtocol

    init(
      _ endpoint: Ocp1FlyingFoxDeviceEndpoint?,
      controlProtocol: OcaControlProtocol,
      peer: HTTPRequest.Address?
    ) {
      self.endpoint = endpoint
      self.controlProtocol = controlProtocol
      identifier = switch peer {
      case let .ip4(address, port), let .ip6(address, port):
        "\(address):\(port)"
      case let .unix(path) where !path.isEmpty:
        path
      default:
        "unknown"
      }
    }

    func makeMessages(for client: AsyncStream<WSMessage>) async throws
      -> AsyncStream<WSMessage>
    {
      AsyncStream<WSMessage> { continuation in
        let controller = Ocp1FlyingFoxController(
          endpoint: endpoint,
          controlProtocol: controlProtocol,
          identifier: identifier,
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

  /// Serves each of `controlProtocols` at its path in `paths`, or at `/`. Protocols
  /// sharing a path are told apart by the subprotocol the client offers: `AES70-OCP.2`
  /// for OCP.2, none for OCP.1.
  public convenience init(
    address: Data,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    controlProtocols: Set<OcaControlProtocol> = [.ocp1],
    paths: [OcaControlProtocol: String] = [:],
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1FlyingFoxDeviceEndpoint")
  ) async throws {
    var storage = sockaddr_storage()
    _ = withUnsafeMutableBytes(of: &storage) { dst in
      address.withUnsafeBytes { src in
        memcpy(dst.baseAddress!, src.baseAddress!, src.count)
      }
    }
    try await self.init(
      address: storage,
      timeout: timeout,
      device: device,
      controlProtocols: controlProtocols,
      paths: paths,
      logger: logger
    )
  }

  private init(
    address: sockaddr_storage,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    controlProtocols: Set<OcaControlProtocol> = [.ocp1],
    paths: [OcaControlProtocol: String] = [:],
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1FlyingFoxDeviceEndpoint")
  ) async throws {
    guard !controlProtocols.isEmpty else { throw Ocp1Error.unsupportedControlProtocol }
    self.device = device
    self.address = address
    self.timeout = timeout
    self.paths = Dictionary(uniqueKeysWithValues: controlProtocols.map { controlProtocol in
      let path = paths[controlProtocol] ?? "/"
      return (controlProtocol, path.hasPrefix("/") ? path : "/" + path)
    })
    self.logger = logger

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

    // one route per path; the protocols sharing it are told apart by the subprotocol
    let routes = Dictionary(grouping: self.paths, by: \.value).mapValues { $0.map(\.key) }
    for (path, sharing) in routes {
      await httpServer.appendRoute(HTTPRoute("GET \(path)")) { [weak self] request in
        let offered = request.headers[Self.webSocketProtocolHeader]?
          .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let controlProtocol = Self.controlProtocol(offering: offered, among: sharing)
        // one handler per upgrade, so the controller knows its peer
        var response = try await WebSocketHTTPHandler
          .webSocket(Handler(self, controlProtocol: controlProtocol, peer: request.remoteAddress))
          .handleRequest(request)
        // RFC 6455 4.2.2: echo the subprotocol we speak if the client offered it
        if let subprotocol = controlProtocol.webSocketSubprotocol,
           response.statusCode == .switchingProtocols, offered.contains(subprotocol)
        {
          response.headers[Self.webSocketProtocolHeader] = subprotocol
        }
        return response
      }
    }

    try await device.add(endpoint: self)
  }

  nonisolated static let webSocketProtocolHeader = HTTPHeader("Sec-WebSocket-Protocol")

  public nonisolated var description: String {
    "\(type(of: self))(address: \(address._presentationAddress), timeout: \(timeout))"
  }

  public func run() async throws {
    do {
      if port != 0 {
        #if canImport(dnssd)
        _endpointRegistrarTask = makeBonjourRegistrarTask(for: device)
        #endif
      }
      try await httpServer.run()
    } catch {
      throw error
    }
  }

  /// The protocols served, in `OcaControlProtocol` order.
  public nonisolated var controlProtocols: [OcaControlProtocol] {
    OcaControlProtocol.allCases.filter { paths[$0] != nil }
  }

  /// The protocol a WebSocket upgrade on a shared path speaks: the one whose subprotocol
  /// the client offered, else the one with none (OCP.1), else the first, as a client need
  /// not offer a subprotocol at all.
  nonisolated static func controlProtocol(
    offering offered: [String],
    among sharing: [OcaControlProtocol]
  ) -> OcaControlProtocol {
    let sharing = OcaControlProtocol.allCases.filter(sharing.contains)
    return sharing.first { $0.webSocketSubprotocol.map(offered.contains) ?? false }
      ?? sharing.first { $0.webSocketSubprotocol == nil }
      ?? sharing[0]
  }

  /// The first protocol's service; `advertisedServices` has one per protocol.
  public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    advertisedServices[0].serviceType
  }

  public nonisolated var txtRecordAdditions: [(String, String)] {
    advertisedServices[0].txtRecordAdditions
  }

  public nonisolated var advertisedServices: [(
    serviceType: OcaNetworkAdvertisingServiceType,
    txtRecordAdditions: [(String, String)]
  )] {
    controlProtocols.map { controlProtocol in
      let path = paths[controlProtocol]!
      return (
        OcaNetworkAdvertisingServiceType.tcpWebSocket.withControlProtocol(controlProtocol),
        path == "/" ? [] : [("path", path)]
      )
    }
  }

  public nonisolated var port: UInt16 {
    (try? address.port) ?? 0
  }

  package func add(controller: Ocp1FlyingFoxController) async {
    _controllers.append(controller)
  }

  package func remove(controller: Ocp1FlyingFoxController) async {
    _controllers.removeAll(where: { $0.id == controller.id })
  }
}
#endif
