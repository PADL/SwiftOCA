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
#if NonEmbeddedBuild
import SwiftOCASecure
import SwiftOCASecureDevice
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
import SocketAddress // for the Windows sa_family_t typealias
#endif

final class DeviceEventDelegate: OcaDeviceEventDelegate {
  func onEvent(_ event: SwiftOCA.OcaEvent, parameters: Data) async {}
  func onControllerExpiry(_ controller: OcaController) async {}
}

@main
public enum DeviceApp {
  nonisolated(unsafe) static var testActuator: SwiftOCADevice.OcaBooleanActuator?
  static let port: UInt16 = 65000
  #if NonEmbeddedBuild
  static let securePort: UInt16 = 65010

  /// PEM paths take precedence over PKCS#12; `nil` falls back to PSK-only.
  static func tlsCredentialFromEnvironment() -> Ocp1TLSCredential? {
    let env = ProcessInfo.processInfo.environment
    if let certPath = env["OCA_TLS_CERT_FILE"], let keyPath = env["OCA_TLS_KEY_FILE"] {
      return .certificateFile(certPath: certPath, keyPath: keyPath)
    }
    if let pkcs12Path = env["OCA_TLS_PKCS12_FILE"],
       let data = try? Data(contentsOf: URL(fileURLWithPath: pkcs12Path))
    {
      return .pkcs12(data: data, password: env["OCA_TLS_PKCS12_PASSWORD"])
    }
    return nil
  }

  /// CA bundle for mTLS; when set, every client must present a chain to it.
  static func clientTrustRootsFromEnvironment() -> Ocp1TLSTrustRoots? {
    ProcessInfo.processInfo.environment["OCA_TLS_CLIENT_CA_FILE"].map { .caFile($0) }
  }
  #endif

  public static func main() async throws {
    var listenAddress = sockaddr_in()
    listenAddress.sin_family = sa_family_t(AF_INET)
    #if canImport(WinSDK)
    listenAddress.sin_addr.S_un.S_addr = 0 // INADDR_ANY
    #else
    listenAddress.sin_addr.s_addr = 0 // INADDR_ANY equivalent
    #endif
    listenAddress.sin_port = port.bigEndian
    #if canImport(Darwin) || os(FreeBSD) || os(OpenBSD)
    listenAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif

    var listen6Address = sockaddr_in6()
    listen6Address.sin6_family = sa_family_t(AF_INET6)
    listen6Address.sin6_addr = in6addr_any
    listen6Address.sin6_port = port.bigEndian
    #if canImport(Darwin)
    listen6Address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    #endif

    let device = OcaDevice.shared
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    Task { @OcaDevice in
      deviceManager.deviceName = "OCA Test"
      deviceManager.serialNumber = "OCADevice-00000001"
      deviceManager.modelGUID = OcaModelGUID(mfrCode: .init((0, 0, 0)), modelCode: (1, 2, 3, 4))
    }
    let delegate = DeviceEventDelegate()
    await device.setEventDelegate(delegate)

    #if os(Linux) && NonEmbeddedBuild
    let streamEndpoint = try await Ocp1IORingStreamDeviceEndpoint(address: listenAddress.data)
    let datagramEndpoint = try await Ocp1IORingDatagramDeviceEndpoint(address: listenAddress.data)
    let stream6Endpoint = try await Ocp1IORingStreamDeviceEndpoint(address: listen6Address.data)
    let datagram6Endpoint = try await Ocp1IORingDatagramDeviceEndpoint(address: listen6Address.data)
    let domainSocketStreamEndpoint =
      try? await Ocp1IORingStreamDeviceEndpoint(path: "/tmp/oca-device.sock")
    let domainSocketDatagramEndpoint =
      try? await Ocp1IORingDatagramDeviceEndpoint(path: "/tmp/oca-device-dg.sock")
    #elseif canImport(FlyingSocks) && NonEmbeddedBuild
    let streamEndpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(address: listenAddress.data)
    let stream6Endpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(
      address: listen6Address
        .data
    )
    #if !os(Windows)
    // FlyingSocks has no Winsock sendmsg, so datagram device endpoints (and the
    // Unix-domain demo socket path) are unavailable on Windows.
    let datagramEndpoint =
      try await Ocp1FlyingSocksDatagramDeviceEndpoint(address: listenAddress.data)
    let datagram6Endpoint = try await Ocp1FlyingSocksDatagramDeviceEndpoint(
      address: listen6Address
        .data
    )
    let domainSocketStreamEndpoint =
      try? await Ocp1FlyingSocksStreamDeviceEndpoint(path: "/tmp/oca-device.sock")
    #endif
    #else
    let streamEndpoint = try await Ocp1DeviceEndpoint(address: listenAddress.data)
    #endif

    #if canImport(FlyingFox) && NonEmbeddedBuild
    listenAddress.sin_family = sa_family_t(AF_INET)
    #if canImport(WinSDK)
    listenAddress.sin_addr.S_un.S_addr = 0 // INADDR_ANY
    #else
    listenAddress.sin_addr.s_addr = 0 // INADDR_ANY equivalent
    #endif
    listenAddress.sin_port = (port + 2).bigEndian
    #if canImport(Darwin) || os(FreeBSD) || os(OpenBSD)
    listenAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    let webSocketEndpoint = try await Ocp1WSDeviceEndpoint(address: listenAddress.data)
    #endif
    #if canImport(Darwin)
    let machPortEndpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: "com.padl.OCADevice",
      device: device
    )
    #endif

    #if (canImport(Network) || (canImport(COpenSSL) && canImport(IORing))) && NonEmbeddedBuild
    // Demo PSK preload (NOT a real credential) for smoke-testing the
    // ocasec/tcp transport when no cert env vars are set. Cert env vars:
    //   OCA_TLS_CERT_FILE / OCA_TLS_KEY_FILE     — PEM
    //   OCA_TLS_PKCS12_FILE / OCA_TLS_PKCS12_PASSWORD — PKCS#12
    let secureCredential = Self.tlsCredentialFromEnvironment()
    if secureCredential == nil, let securityManager = await device.securityManager {
      await Task { @OcaDevice in
        try? securityManager.loadPreSharedKey(
          identity: OcaPreSharedKeyIdentityHint,
          key: Data(repeating: 0, count: 32)
        )
      }.value
    }
    let secureStreamEndpoint = try await Ocp1TLSStreamDeviceEndpoint(
      port: securePort,
      credential: secureCredential,
      clientCertificateTrustRoots: Self.clientTrustRootsFromEnvironment()
    )
    let secureDatagramEndpoint = try await Ocp1TLSDatagramDeviceEndpoint(
      port: securePort,
      credential: secureCredential,
      clientCertificateTrustRoots: Self.clientTrustRootsFromEnvironment()
    )
    #endif

    class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator {
      override open class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }
    }

    let blockONo: OcaONo = 10000
    let matrixONo: OcaONo = 10001
    let firstActuatorONo: OcaONo = 10010
    let gainONo: OcaONo = 10020

    let matrix = try await SwiftOCADevice
      .OcaMatrix<MyBooleanActuator>(
        rows: 4,
        columns: 2,
        objectNumber: matrixONo,
        deviceDelegate: device
      )

    let block = try await SwiftOCADevice
      .OcaBlock<SwiftOCADevice.OcaWorker>(
        objectNumber: blockONo,
        role: "Block",
        deviceDelegate: device
      )

    let members = await matrix.members
    var actuatorONo = firstActuatorONo
    for x in 0..<members.nX {
      for y in 0..<members.nY {
        let coordinate = OcaVector2D(x: OcaMatrixCoordinate(x), y: OcaMatrixCoordinate(y))
        let actuator = try await MyBooleanActuator(
          objectNumber: actuatorONo,
          role: "Actuator(\(x),\(y))",
          deviceDelegate: device,
          addToRootBlock: false
        )
        actuatorONo += 1
        try await block.add(actionObject: actuator)
        try await matrix.add(member: actuator, at: coordinate)
      }
    }

    let gain = try await SwiftOCADevice.OcaGain(
      objectNumber: gainONo,
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await block.add(actionObject: gain)

    #if NonEmbeddedBuild
    try await serializeDeserialize(device.rootBlock)
    #endif

    let controlNetwork = try await SwiftOCADevice.OcaControlNetwork(deviceDelegate: device)
    Task { @OcaDevice in controlNetwork.state = .running }

    #if !os(Windows)
    // Windows has no SIGPIPE; write failures surface as socket errors instead.
    signal(SIGPIPE, SIG_IGN)
    #endif

    Task { @OcaDevice in
      for try await value in gain.$gain {
        print("gain set to \(value)!")
      }
    }

    #if NonEmbeddedBuild
    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
      taskGroup.addTask {
        print("Starting OCP.1 IPv4 stream endpoint \(streamEndpoint)...")
        try await streamEndpoint.run()
      }
      taskGroup.addTask {
        print("Starting OCP.1 IPv6 stream endpoint \(stream6Endpoint)...")
        try await stream6Endpoint.run()
      }
      #if os(Linux) || (canImport(FlyingSocks) && !os(Windows))
      taskGroup.addTask {
        print("Starting OCP.1 IPv4 datagram endpoint \(datagramEndpoint)...")
        try await datagramEndpoint.run()
      }
      taskGroup.addTask {
        print("Starting OCP.1 IPv6 datagram endpoint \(datagram6Endpoint)...")
        try await datagram6Endpoint.run()
      }
      if let domainSocketStreamEndpoint {
        taskGroup.addTask {
          print("Starting OCP.1 domain socket stream endpoint \(domainSocketStreamEndpoint)...")
          try await domainSocketStreamEndpoint.run()
        }
      }
      #endif
      #if os(Linux)
      if let domainSocketDatagramEndpoint {
        taskGroup.addTask {
          print("Starting OCP.1 domain socket datagram endpoint \(domainSocketDatagramEndpoint)...")
          try await domainSocketDatagramEndpoint.run()
        }
      }
      #endif
      #if canImport(FlyingSocks)
      taskGroup.addTask {
        print("Starting OCP.1 WebSocket endpoint \(webSocketEndpoint)...")
        try await webSocketEndpoint.run()
      }
      #endif
      #if canImport(Darwin)
      taskGroup.addTask {
        print("Starting OCP.1 Mach port endpoint \(machPortEndpoint)...")
        try await machPortEndpoint.run()
      }
      #endif
      #if canImport(Network) || (canImport(COpenSSL) && canImport(IORing))
      taskGroup.addTask {
        print("Starting OCP.1 TLS stream endpoint \(secureStreamEndpoint)...")
        try await secureStreamEndpoint.run()
      }
      taskGroup.addTask {
        print("Starting OCP.1 DTLS datagram endpoint \(secureDatagramEndpoint)...")
        try await secureDatagramEndpoint.run()
      }
      #endif
      try await taskGroup.next()
    }
    #else
    print("Starting OCP.1 IPv4 stream endpoint \(streamEndpoint)...")
    try await streamEndpoint.run()
    #endif
  }
}

#if NonEmbeddedBuild
func serializeDeserialize(
  _ object: SwiftOCADevice
    .OcaBlock<SwiftOCADevice.OcaRoot>
) async throws {
  do {
    let jsonResultData = try await JSONSerialization.data(withJSONObject: object.jsonObject)
    print(String(data: jsonResultData, encoding: .utf8)!)

    let decoded = try JSONSerialization.jsonObject(with: jsonResultData) as! [String: any Sendable]
    try await OcaDevice.shared.deserialize(jsonObject: decoded)
  } catch {
    debugPrint("serialization error: \(error)")
  }
}
#endif
