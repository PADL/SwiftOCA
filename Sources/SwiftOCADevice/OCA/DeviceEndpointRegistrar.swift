//
// Copyright (c) 2023 PADL Software Pty Ltd
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
#endif
import Dispatch
import dnssd

/// A helper class for advertising OCP.1 endpoints using Bonjour

public protocol OcaBonjourRegistrableDeviceEndpoint: OcaDeviceEndpoint {
  var serviceType: OcaDeviceEndpointRegistrar.ServiceType { get }
  var port: UInt16 { get }
}

@OcaDevice
public final class OcaDeviceEndpointRegistrar: @unchecked Sendable {
  public typealias Handle = ObjectIdentifier

  public static let shared = OcaDeviceEndpointRegistrar()

  private struct EndpointRegistration {
    let endpoint: OcaBonjourRegistrableDeviceEndpoint
    let service: Service
  }

  private var services = [EndpointRegistration]()

  // FIXME: copied from OcaBrowser.swift
  public enum ServiceType: String {
    case none = ""
    case tcp = "_oca._tcp."
    case tcpSecure = "_ocasec._tcp."
    case udp = "_oca._udp."
    case tcpWebSocket = "_ocaws._tcp."
  }

  public func register(
    endpoint: any OcaBonjourRegistrableDeviceEndpoint,
    device: OcaDevice
  ) async throws
    -> Handle
  {
    let txtRecords: [String: String] = if let deviceManager = await device.deviceManager {
      [
        "txtvers": "1",
        "protovers": "\(deviceManager.version)",
        "modelGUID": "\(deviceManager.modelGUID)",
      ]
    } else {
      [:]
    }
    let service = try await Service(
      regType: endpoint.serviceType.rawValue,
      port: endpoint.port,
      txtRecord: txtRecords
    )
    let endpointRegistration = EndpointRegistration(endpoint: endpoint, service: service)
    services.append(endpointRegistration)
    return ObjectIdentifier(endpointRegistration.service)
  }

  public func deregister(handle: Handle) async throws {
    services.removeAll(where: { ObjectIdentifier($0.service) == handle })
  }

  fileprivate final class Service: @unchecked Sendable {
    var sdRef: DNSServiceRef!
    var flags: DNSServiceFlags = 0
    var name: String!
    var domain: String!

    deinit {
      if let sdRef {
        DNSServiceRefDeallocate(sdRef)
      }
    }

    typealias RegisterReply = (DNSServiceFlags, String, String)

    var registrationContinuation: CheckedContinuation<RegisterReply, Error>?

    init(
      flags: DNSServiceFlags = 0,
      interfaceIndex: UInt32 = UInt32(kDNSServiceInterfaceIndexAny),
      name: String? = nil,
      regType: String,
      domain: String? = nil,
      host: String? = nil,
      port: UInt16, // in host byte order, unlike DNSServiceRegister() API
      txtRecord: [String: String] = [:]
    ) async throws {
      let txtRecordBuffer: [UInt8] = txtRecord.flatMap { key, value in
        // FIXME: escape
        let keyValue = "\(key)=\(value)".utf8
        return [UInt8(keyValue.count)] + keyValue
      }

      let reply: RegisterReply = try await withCheckedThrowingContinuation { continuation in
        self.registrationContinuation = continuation

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
          continuation
            .resume(
              throwing: DNSServiceError(rawValue: error) ?? DNSServiceError
                .unknown
            )
          return
        }
      }

      self.flags = reply.0
      self.name = reply.1
      self.domain = reply.2
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
  let service = Unmanaged<OcaDeviceEndpointRegistrar.Service>.fromOpaque(context!)
    .takeRetainedValue()
  let continuation = service.registrationContinuation!

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
    continuation.resume(throwing: DNSServiceError(rawValue: error) ?? DNSServiceError.unknown)
    return
  }
  let reply = (
    flags,
    String(cString: name!),
    String(cString: domain!)
  )
  continuation.resume(returning: reply)
  service.registrationContinuation = nil
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
