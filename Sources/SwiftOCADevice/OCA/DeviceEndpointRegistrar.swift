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

#if canImport(dnssd)

import SwiftOCA
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif
import Dispatch
import dnssd
import Logging

/// A helper class for advertising OCP.1 endpoints using Bonjour

public protocol OcaBonjourRegistrableDeviceEndpoint: OcaDeviceEndpoint {
  var serviceType: OcaNetworkAdvertisingServiceType { get }
  var port: UInt16 { get }
}

extension OcaDeviceManager {
  var txtRecords: [String: String] {
    [
      "txtvers": "1",
      "protovers": "\(version)",
      "modelGUID": "\(modelGUID)",
      "serialNumber": "\(serialNumber)",
    ]
  }
}

extension OcaBonjourRegistrableDeviceEndpoint {
  // this will run a registration loop until cancelled
  @OcaDevice
  func runBonjourEndpointRegistrar(for device: OcaDevice) async throws {
    let logger = await device.logger
    let deviceManager = await device.deviceManager!
    var dnsServiceRegistration: DNSServiceRegistration?

    logger.trace("starting DNS endpoint registration task")

    for try await deviceName in deviceManager.$deviceName {
      try await Task.checkCancellation()
      await dnsServiceRegistration?.deregister()
      dnsServiceRegistration = try? DNSServiceRegistration(
        name: deviceName,
        regType: serviceType.rawValue,
        port: port,
        txtRecord: deviceManager.txtRecords
      )
    }

    await dnsServiceRegistration?.deregister()
    logger.trace("ending DNS endpoint registration task")
  }
}

fileprivate actor DNSServiceRegistration {
  private var sdRef: DNSServiceRef!
  private(set) var flags: DNSServiceFlags = 0
  private(set) var name: String?
  private(set) var domain: String?
  private(set) var lastError = DNSServiceErrorType(kDNSServiceErr_NoError)

  func callBack(
    flags: DNSServiceFlags,
    error: DNSServiceErrorType,
    name: String?,
    regType: String?,
    domain: String?
  ) {
    self.flags = flags
    self.name = name
    self.domain = domain
    lastError = error
  }

  init(
    flags: DNSServiceFlags = 0,
    interfaceIndex: UInt32 = UInt32(kDNSServiceInterfaceIndexAny),
    name: String? = nil,
    regType: String,
    domain: String? = nil,
    host: String? = nil,
    port: UInt16, // in host byte order, unlike DNSServiceRegister() API
    txtRecord: [String: String] = [:]
  ) throws {
    self.flags = flags
    self.name = name
    self.domain = domain

    let txtRecordBuffer: [UInt8] = txtRecord.flatMap { key, value in
      // FIXME: escape
      let keyValue = "\(key)=\(value)".utf8
      return [UInt8(keyValue.count)] + keyValue
    }

    var sdRef: DNSServiceRef?

    let error = txtRecordBuffer.withUnsafeBufferPointer { txtRecordBufferPointer in
      DNSServiceRegister(
        &sdRef,
        flags,
        interfaceIndex,
        name,
        regType,
        domain,
        host,
        port.bigEndian,
        UInt16(txtRecordBufferPointer.count),
        txtRecordBufferPointer.baseAddress,
        DNSServiceRegisterBlock_Thunk,
        Unmanaged.passRetained(self).toOpaque()
      )
    }

    guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
      throw DNSServiceError(rawValue: error) ?? DNSServiceError.unknown
    }

    self.sdRef = sdRef
  }

  func deregister() {
    if let sdRef {
      DNSServiceRefDeallocate(sdRef)
      self.sdRef = nil
    }
  }

  deinit {
    if let sdRef {
      DNSServiceRefDeallocate(sdRef)
    }
  }
}

@_cdecl("DNSServiceRegisterBlock_Thunk")
private func DNSServiceRegisterBlock_Thunk(
  _ sdRef: DNSServiceRef?,
  _ flags: DNSServiceFlags,
  _ error: DNSServiceErrorType,
  _ name: UnsafePointer<CChar>?,
  _ regType: UnsafePointer<CChar>?,
  _ domain: UnsafePointer<CChar>?,
  _ context: UnsafeMutableRawPointer?
) {
  let service = Unmanaged<DNSServiceRegistration>.fromOpaque(context!)
    .takeRetainedValue()

  let name = name != nil ? String(cString: name!) : nil
  let regType = regType != nil ? String(cString: regType!) : nil
  let domain = domain != nil ? String(cString: domain!) : nil

  Task { @Sendable in
    await service.callBack(
      flags: flags,
      error: error, name: name, regType: regType, domain: domain
    )
  }
}

public enum DNSServiceError: Int32, Error {
  case noError = 0
  case unknown = -65537
  case noSuchName = -65538
  case noMemory = -65539
  case badParam = -65540
  case badReference = -65541
  case badState = -65542
  case badFlags = -65543
  case unsupported = -65544
  case notInitialized = -65545
  case alreadyRegistered = -65547
  case nameConflict = -65548
  case invalid = -65549
  case firewall = -65550
  case incompatible = -65551
  case badInterfaceIndex = -65552
  case refused = -65553
  case noSuchRecord = -65554
  case noAuth = -65555
  case NoSuchKey = -65556
  case NATTraversal = -65557
  case noubleNAT = -65558
  case badTime = -65559
  case badSig = -65560
  case badKey = -65561
  case transient = -65562
  case serviceNotRunning = -65563
  case NATPortMappingUnsupported = -65564
  case NATPortMappingDisabled = -65565
  case noRouter = -65566
  case pollingMode = -65567
  case timeout = -65568
  case defunctConnection = -65569
  case policyDenied = -65570
  case notPermitted = -65571
}

#else

public protocol OcaBonjourRegistrableDeviceEndpoint: OcaDeviceEndpoint {}

#endif
