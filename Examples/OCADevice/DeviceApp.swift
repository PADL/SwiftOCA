//
// Copyright (c) 2023-2025 PADL Software Pty Ltd
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

import Foundation
import SwiftOCA
import SwiftOCADevice
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

final class DeviceEventDelegate: OcaDeviceEventDelegate {
  public func onEvent(_ event: SwiftOCA.OcaEvent, parameters: Data) async {}
  public func onControllerExpiry(_ controller: OcaController) async {}
}

@main
public enum DeviceApp {
  static var testActuator: SwiftOCADevice.OcaBooleanActuator?
  static let port: UInt16 = 65000

  public static func main() async throws {
    var listenAddress = sockaddr_in()
    listenAddress.sin_family = sa_family_t(AF_INET)
    listenAddress.sin_addr.s_addr = INADDR_ANY
    listenAddress.sin_port = port.bigEndian
    #if canImport(Darwin)
    listenAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif

    var listen6Address = sockaddr_in6()
    listen6Address.sin6_family = sa_family_t(AF_INET6)
    listen6Address.sin6_addr = in6addr_any
    listen6Address.sin6_port = (port + 1).bigEndian
    #if canImport(Darwin)
    listen6Address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    #endif

    let device = OcaDevice.shared
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    Task { @OcaDevice in
      deviceManager.deviceName = "OCA Test"
      deviceManager.modelGUID = OcaModelGUID(mfrCode: .init((0, 0, 0)), modelCode: (1, 2, 3, 4))
    }
    let delegate = DeviceEventDelegate()
    await device.setEventDelegate(delegate)
    #if os(Linux)
    let streamEndpoint = try await Ocp1IORingStreamDeviceEndpoint(address: listenAddress.data)
    let datagramEndpoint = try await Ocp1IORingDatagramDeviceEndpoint(address: listenAddress.data)
    let stream6Endpoint = try await Ocp1IORingStreamDeviceEndpoint(address: listen6Address.data)
    let datagram6Endpoint = try await Ocp1IORingDatagramDeviceEndpoint(address: listen6Address.data)
    let domainSocketStreamEndpoint =
      try? await Ocp1IORingStreamDeviceEndpoint(path: "/tmp/oca-device.sock")
    let domainSocketDatagramEndpoint =
      try? await Ocp1IORingDatagramDeviceEndpoint(path: "/tmp/oca-device-dg.sock")
    #elseif canImport(FlyingSocks)
    let streamEndpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(address: listenAddress.data)
    let datagramEndpoint =
      try await Ocp1FlyingSocksDatagramDeviceEndpoint(address: listenAddress.data)
    let stream6Endpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(
      address: listen6Address
        .data
    )
    let datagram6Endpoint = try await Ocp1FlyingSocksDatagramDeviceEndpoint(
      address: listen6Address
        .data
    )
    #else
    let streamEndpoint = try await Ocp1StreamDeviceEndpoint(address: listenAddress.data)
    #endif
    #if canImport(FlyingSocks)
    listenAddress.sin_family = sa_family_t(AF_INET)
    listenAddress.sin_addr.s_addr = INADDR_ANY
    listenAddress.sin_port = (port + 2).bigEndian
    listenAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    let webSocketEndpoint = try await Ocp1WSDeviceEndpoint(address: listenAddress.data)
    #endif

    class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator {
      override open class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }
    }

    let matrix = try await SwiftOCADevice
      .OcaMatrix<MyBooleanActuator>(
        rows: 4,
        columns: 2,
        deviceDelegate: device
      )

    let block = try await SwiftOCADevice
      .OcaBlock<SwiftOCADevice.OcaWorker>(role: "Block", deviceDelegate: device)

    let members = await matrix.members
    for x in 0..<members.nX {
      for y in 0..<members.nY {
        let coordinate = OcaVector2D(x: OcaMatrixCoordinate(x), y: OcaMatrixCoordinate(y))
        let actuator = try await MyBooleanActuator(
          role: "Actuator(\(x),\(y))",
          deviceDelegate: device,
          addToRootBlock: false
        )
        try await block.add(actionObject: actuator)
        try await matrix.add(member: actuator, at: coordinate)
      }
    }

    let gain = try await SwiftOCADevice.OcaGain(
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await block.add(actionObject: gain)

    try await serializeDeserialize(device.rootBlock)

    let controlNetwork = try await SwiftOCADevice.OcaControlNetwork(deviceDelegate: device)
    Task { @OcaDevice in controlNetwork.state = .running }

    signal(SIGPIPE, SIG_IGN)

    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
      taskGroup.addTask {
        print("Starting OCP.1 IPv4 stream endpoint \(streamEndpoint)...")
        try await streamEndpoint.run()
      }
      taskGroup.addTask {
        print("Starting OCP.1 IPv6 stream endpoint \(stream6Endpoint)...")
        try await stream6Endpoint.run()
      }
      #if os(Linux) || canImport(FlyingSocks)
      taskGroup.addTask {
        print("Starting OCP.1 IPv4 datagram endpoint \(datagramEndpoint)...")
        try await datagramEndpoint.run()
      }
      taskGroup.addTask {
        print("Starting OCP.1 IPv6 datagram endpoint \(datagram6Endpoint)...")
        try await datagram6Endpoint.run()
      }
      #endif
      #if canImport(FlyingSocks)
      taskGroup.addTask {
        print("Starting OCP.1 WebSocket endpoint \(webSocketEndpoint)...")
        try await webSocketEndpoint.run()
      }
      #endif
      #if os(Linux)
      if let domainSocketStreamEndpoint {
        taskGroup.addTask {
          print("Starting OCP.1 domain socket stream endpoint \(domainSocketStreamEndpoint)...")
          try await domainSocketStreamEndpoint.run()
        }
      }
      if let domainSocketDatagramEndpoint {
        taskGroup.addTask {
          print("Starting OCP.1 domain socket datagram endpoint \(domainSocketDatagramEndpoint)...")
          try await domainSocketDatagramEndpoint.run()
        }
      }
      #endif
      taskGroup.addTask {
        for try await value in await gain.$gain {
          print("gain set to \(value)!")
        }
      }
      try await taskGroup.next()
    }
  }
}

func serializeDeserialize(
  _ object: SwiftOCADevice
    .OcaBlock<SwiftOCADevice.OcaRoot>
) async throws {
  do {
    let jsonResultData = try await JSONSerialization.data(withJSONObject: object.jsonObject)
    print(String(data: jsonResultData, encoding: .utf8)!)

    let decoded = try JSONSerialization.jsonObject(with: jsonResultData) as! [String: Any]
    try await OcaDevice.shared.deserialize(jsonObject: decoded)
  } catch {
    debugPrint("serialization error: \(error)")
  }
}
