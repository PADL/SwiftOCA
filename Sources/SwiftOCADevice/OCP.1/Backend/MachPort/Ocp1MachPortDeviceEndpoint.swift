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

#if canImport(Darwin)

import AsyncExtensions
import Darwin.Mach
import Foundation
import Logging
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// OCP.1 device endpoint using Mach ports for fast local IPC.
///
/// Registers a bootstrap service name and listens for incoming Mach port
/// connections. Each connecting controller gets a dedicated pair of ports
/// for bidirectional OCP.1 PDU exchange.
@OcaDevice
public final class Ocp1MachPortDeviceEndpoint: OcaDeviceEndpointPrivate, CustomStringConvertible {
  typealias ControllerType = Ocp1MachPortController

  let timeout: Duration
  let device: OcaDevice
  let logger: Logger
  nonisolated(unsafe) var enableMessageTracing = false

  public var controllers: [OcaController] {
    _controllers
  }

  private let serviceName: String
  private var listenerHandle: Ocp1MachPortHandle?
  private var _controllers = [Ocp1MachPortController]()
  private var nextControllerID = 0

  public init(
    serviceName: String,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(
      label: "com.padl.SwiftOCADevice.Ocp1MachPortDeviceEndpoint"
    )
  ) async throws {
    self.serviceName = serviceName
    self.timeout = timeout
    self.device = device
    self.logger = logger

    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    "\(type(of: self))(serviceName: \(serviceName))"
  }

  public func run() async throws {
    let handle = try Ocp1MachPortHandle.allocateReceivePort()
    listenerHandle = handle

    try Ocp1MachPortBootstrap.register(
      serviceName: serviceName,
      port: handle.port
    )

    logger.info("started \(type(of: self)) on \(serviceName)")

    do {
      try await listenForControllers(on: handle)
    } catch {
      logger.critical("server error for \(serviceName): \(error)")
      handle.destroy()
      listenerHandle = nil
      throw error
    }

    try await device.remove(endpoint: self)
  }

  private func listenForControllers(on listenerHandle: Ocp1MachPortHandle) async throws {
    let acceptStream = AsyncThrowingStream<Ocp1MachPortEnvelope, Error> { continuation in
      DispatchQueue(
        label: "com.padl.SwiftOCADevice.machAccept"
      ).async {
        do {
          while true {
            let envelope = try listenerHandle.receive()
            continuation.yield(envelope)
          }
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }

    try await withThrowingDiscardingTaskGroup { group in
      for try await envelope in acceptStream {
        guard envelope.kind == .connect,
              envelope.transferredPort != mach_port_t(0)
        else {
          envelope.dispose()
          continue
        }

        let clientSendPort = envelope.transferredPort
        let replyPort = envelope.replyPort

        // Allocate a dedicated controller receive port and create a send
        // right to transfer to the client via the connectReply.
        let controllerHandle: Ocp1MachPortHandle
        let controllerSendRight: mach_port_t
        do {
          controllerHandle = try Ocp1MachPortHandle.allocateReceivePort()
          controllerSendRight = try controllerHandle.makeSendRight()
        } catch {
          Ocp1MachPortHandle.deallocateSendRight(clientSendPort)
          Ocp1MachPortHandle.deallocateSendRight(replyPort)
          logger.warning("failed to allocate controller port: \(error)")
          continue
        }

        do {
          try controllerHandle.sendPortTransfer(
            to: replyPort,
            id: .connectReply,
            transferPort: controllerSendRight
          )
        } catch {
          Ocp1MachPortHandle.deallocateSendRight(clientSendPort)
          Ocp1MachPortHandle.deallocateSendRight(replyPort)
          controllerHandle.destroy()
          logger.warning("failed to send connectReply: \(error)")
          continue
        }

        // Deallocate the reply port send right — no longer needed
        Ocp1MachPortHandle.deallocateSendRight(replyPort)

        let controllerID = nextControllerID
        nextControllerID += 1

        let controller = Ocp1MachPortController(
          endpoint: self,
          receiveHandle: controllerHandle,
          clientSendPort: clientSendPort,
          identifier: "mach-\(controllerID)"
        )

        group.addTask {
          await controller.handle(for: self)
        }
      }
    }
  }

  func add(controller: ControllerType) async {
    _controllers.append(controller)
  }

  func remove(controller: ControllerType) async {
    _controllers.removeAll(where: { $0 == controller })
  }
}

#endif
