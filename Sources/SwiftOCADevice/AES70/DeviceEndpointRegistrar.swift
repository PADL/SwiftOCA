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

import SwiftOCA
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Dispatch
import dnssd

/// A helper class for advertising OCP.1 endpoints using Bonjour

public protocol AES70BonjourRegistrableDeviceEndpoint: AES70DeviceEndpoint {
    var serviceType: AES70DeviceEndpointRegistrar.ServiceType { get }
    var port: UInt16 { get }
}

public final class AES70DeviceEndpointRegistrar {
    public typealias Handle = ObjectIdentifier

    public static let shared = AES70DeviceEndpointRegistrar()

    private struct EndpointRegistration {
        let endpoint: AES70BonjourRegistrableDeviceEndpoint
        let service: Service
    }

    private var services = [EndpointRegistration]()

    // FIXME: copied from AES70Browser.swift
    public enum ServiceType: String {
        case tcp = "_oca._tcp."
        case tcpSecure = "_ocasec._tcp."
        case udp = "_oca._udp."
        case tcpWebSocket = "_ocaws._tcp."
    }

    public func register(endpoint: any AES70BonjourRegistrableDeviceEndpoint) async throws
        -> Handle
    {
        let service = try await Service(
            regType: endpoint.serviceType.rawValue,
            port: endpoint.port.bigEndian
        )
        let endpointRegistration = EndpointRegistration(endpoint: endpoint, service: service)
        services.append(endpointRegistration)
        return ObjectIdentifier(endpointRegistration.service)
    }

    public func deregister(handle: Handle) async throws {
        services.removeAll(where: { ObjectIdentifier($0.service) == handle })
    }

    enum DNSServiceError: Int32, Error {
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

    private class Service {
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

        init(
            flags: DNSServiceFlags = 0,
            interfaceIndex: UInt32 = 0,
            name: String? = nil,
            regType: String,
            domain: String? = nil,
            host: String? = nil,
            port: UInt16,
            txtLen: UInt16 = 0,
            txtRecord: UnsafeRawPointer? = nil
        ) async throws {
            let reply: RegisterReply = try await withCheckedThrowingContinuation { continuation in
                let error = DNSServiceRegisterBlock(
                    &sdRef,
                    flags,
                    interfaceIndex,
                    name,
                    regType,
                    domain,
                    host,
                    port,
                    txtLen,
                    txtRecord
                ) { _, flags, error, name, _, domain in
                    guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
                        continuation
                            .resume(
                                throwing: DNSServiceError(rawValue: error) ?? DNSServiceError
                                    .unknown
                            )
                        return
                    }
                    let reply: RegisterReply = (
                        flags,
                        String(cString: name!),
                        String(cString: domain!)
                    )
                    continuation.resume(returning: reply)
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

private func DNSServiceRegisterBlock_Thunk(
    _ sdRef: DNSServiceRef?,
    _ flags: DNSServiceFlags,
    _ errorCode: DNSServiceErrorType,
    _ name: UnsafePointer<CChar>?,
    _ regType: UnsafePointer<CChar>?,
    _ domain: UnsafePointer<CChar>?,
    _ context: UnsafeMutableRawPointer?
) {
    let block = unsafeBitCast(context, to: DNSServiceRegisterReplyBlock.self)
    block(sdRef, flags, errorCode, name, regType, domain)
    _Block_release(context)
}

private func DNSServiceRegisterBlock(
    _ sdRef: UnsafeMutablePointer<DNSServiceRef?>,
    _ flags: DNSServiceFlags,
    _ interfaceIndex: UInt32,
    _ name: String?,
    _ regType: String,
    _ domain: String?,
    _ host: String?,
    _ port: UInt16,
    _ txtLen: UInt16,
    _ txtRecord: UnsafeRawPointer?,
    _ body: @escaping DNSServiceRegisterReplyBlock
) -> DNSServiceErrorType {
    DNSServiceRegister(
        sdRef,
        flags,
        interfaceIndex,
        name,
        regType,
        domain,
        host,
        port,
        txtLen,
        txtRecord,
        DNSServiceRegisterBlock_Thunk,
        _Block_copy(unsafeBitCast(body, to: UnsafeMutableRawPointer.self))
    )
}
