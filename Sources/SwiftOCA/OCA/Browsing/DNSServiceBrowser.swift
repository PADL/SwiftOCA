//
// Copyright (c) 2025 PADL Software Pty Ltd
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

import AsyncAlgorithms
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif
import Dispatch
import dnssd

/// A private class that represents a discovered DNS-SD service
private final class _DNSServiceInfo: OcaNetworkAdvertisingServiceInfo, @unchecked Sendable {
  var service: OcaNetworkAdvertisingService { .mDNS_DNSSD }
  let serviceType: OcaNetworkAdvertisingServiceType
  let name: String
  let domain: String
  let interfaceIndex: UInt32

  // Context objects for passing to C callbacks
  final class ResolveContext: @unchecked Sendable {
    let continuation: CheckedContinuation<(), Error>
    let serviceInfo: _DNSServiceInfo
    var source: DispatchSourceRead?

    init(continuation: CheckedContinuation<(), Error>, serviceInfo: _DNSServiceInfo) {
      self.continuation = continuation
      self.serviceInfo = serviceInfo
    }
  }

  private struct ResolutionInfo {
    var hostname: String
    var port: UInt16
    var addresses: [Data] = []
    var txtRecords: [String: String] = [:]
  }

  // resolved name and addresses, set (semi-)atomically after resolve() called
  private let _resolutionInfo: ManagedCriticalState<ResolutionInfo?> = .init(nil)

  init(
    name: String,
    serviceType: OcaNetworkAdvertisingServiceType,
    domain: String,
    interfaceIndex: UInt32
  ) {
    self.name = name
    self.serviceType = serviceType
    self.domain = domain
    self.interfaceIndex = interfaceIndex
  }

  var hostname: String {
    get throws {
      guard let hostname = _resolutionInfo.withCriticalRegion({ $0?.hostname }) else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return hostname
    }
  }

  var port: UInt16 {
    get throws {
      guard let port = _resolutionInfo.withCriticalRegion({ $0?.port }) else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return port
    }
  }

  var addresses: [Data] {
    get throws {
      guard let addresses = _resolutionInfo.withCriticalRegion({ $0?.addresses }) else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return addresses
    }
  }

  var txtRecords: [String: String] {
    get throws {
      guard let records = _resolutionInfo.withCriticalRegion({ $0?.txtRecords }) else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return records
    }
  }

  func resolve() async throws {
    // do nothing if already resolved
    guard _resolutionInfo.criticalState == nil else { return }

    try await _resolveService()
    try await _resolveAddresses()
  }

  private func _resolveService() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) in
      var sdRef: DNSServiceRef?

      let resolveContext = ResolveContext(continuation: continuation, serviceInfo: self)
      let context = Unmanaged.passRetained(resolveContext).toOpaque()

      let error = DNSServiceResolve(
        &sdRef,
        0, // flags
        interfaceIndex,
        name,
        serviceType.rawValue,
        domain,
        DNSServiceResolveBlock_Thunk,
        context
      )

      guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let sdRef else {
        Unmanaged<ResolveContext>.fromOpaque(context).release()
        continuation.resume(throwing: Ocp1Error.serviceResolutionFailed)
        return
      }

      let source = DispatchSource.makeReadSource(
        fileDescriptor: DNSServiceRefSockFD(sdRef),
        queue: DispatchQueue(label: "com.padl.SwiftOCA.DNSServiceResolve")
      )

      source.setEventHandler { DNSServiceProcessResult(sdRef) }
      source.setCancelHandler { DNSServiceRefDeallocate(sdRef) }

      resolveContext.source = source
      source.resume()
    }
  }

  private func _resolveAddresses() async throws {
    guard let hostname = _resolutionInfo.withCriticalRegion({ $0?.hostname }) else {
      throw Ocp1Error.serviceResolutionFailed
    }

    // Use POSIX getaddrinfo for portability (DNSServiceGetAddrInfo is not available on Linux)
    try await Task {
      var hints = addrinfo()
      hints.ai_family = AF_UNSPEC // Allow both IPv4 and IPv6
      hints.ai_socktype = SOCK_STREAM

      var result: UnsafeMutablePointer<addrinfo>?
      defer {
        if let result { freeaddrinfo(result) }
      }

      let error = getaddrinfo(hostname, nil, &hints, &result)
      guard error == 0, let result else {
        throw Ocp1Error.serviceResolutionFailed
      }

      for addrInfo in sequence(first: result, next: { $0.pointee.ai_next }) {
        let addrInfo = addrInfo.pointee
        let addressData: Data

        switch addrInfo.ai_family {
        case AF_INET:
          if let addr = addrInfo.ai_addr {
            addressData = withUnsafeBytes(of: addr.pointee) { bytes in
              Data(bytes.prefix(MemoryLayout<sockaddr_in>.size))
            }
            _addAddress(addressData)
          }
        case AF_INET6:
          if let addr = addrInfo.ai_addr {
            addressData = withUnsafeBytes(of: addr.pointee) { bytes in
              Data(bytes.prefix(MemoryLayout<sockaddr_in6>.size))
            }
            _addAddress(addressData)
          }
        default:
          break
        }
      }
    }.value
  }

  fileprivate func _setResolveResult(hostname: String, port: UInt16, txtRecords: [String: String]) {
    _resolutionInfo.withCriticalRegion {
      $0 = ResolutionInfo(hostname: hostname, port: port, txtRecords: txtRecords)
    }
  }

  private func _addAddress(_ address: Data) {
    _resolutionInfo.withCriticalRegion {
      $0?.addresses.append(address)
    }
  }

  nonisolated static func == (lhs: _DNSServiceInfo, rhs: _DNSServiceInfo) -> Bool {
    lhs.name == rhs.name && lhs.serviceType == rhs.serviceType && lhs.domain == rhs.domain
  }

  nonisolated func hash(into hasher: inout Hasher) {
    name.hash(into: &hasher)
    serviceType.hash(into: &hasher)
    domain.hash(into: &hasher)
  }
}

// C callback thunks
@_cdecl("DNSServiceResolveBlock_Thunk")
private func DNSServiceResolveBlock_Thunk(
  _ sdRef: DNSServiceRef?,
  _ flags: DNSServiceFlags,
  _ interfaceIndex: UInt32,
  _ error: DNSServiceErrorType,
  _ fullname: UnsafePointer<CChar>?,
  _ hosttarget: UnsafePointer<CChar>?,
  _ port: UInt16,
  _ txtLen: UInt16,
  _ txtRecord: UnsafePointer<UInt8>?,
  _ context: UnsafeMutableRawPointer?
) {
  guard let context else { return }

  let resolveContext = Unmanaged<_DNSServiceInfo.ResolveContext>.fromOpaque(context)
    .takeRetainedValue()

  defer {
    resolveContext.source?.cancel()
  }

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
    resolveContext.continuation.resume(throwing: Ocp1Error.serviceResolutionFailed)
    return
  }

  guard let hosttarget else {
    resolveContext.continuation.resume(throwing: Ocp1Error.serviceResolutionFailed)
    return
  }

  let hostname = String(cString: hosttarget)
  let hostPort = UInt16(bigEndian: port)

  // Parse TXT records
  var txtRecords: [String: String] = [:]
  if txtLen > 0, let txtRecord {
    var offset = 0
    while offset < txtLen {
      let recordLength = Int(txtRecord[offset])
      offset += 1

      guard offset + recordLength <= txtLen else { break }

      let recordData = Data(bytes: txtRecord.advanced(by: offset), count: recordLength)
      offset += recordLength

      if let record = String(data: recordData, encoding: .utf8) {
        let components = record.split(
          separator: "=",
          maxSplits: 1,
          omittingEmptySubsequences: false
        )
        let key = String(components[0])
        let value = components.count > 1 ? String(components[1]) : ""
        txtRecords[key] = value
      }
    }
  }

  resolveContext.serviceInfo._setResolveResult(
    hostname: hostname,
    port: hostPort,
    txtRecords: txtRecords
  )
  resolveContext.continuation.resume(returning: ())
}

/// A DNS-SD browser implementation using dns_sd.h
public final class OcaDNSServiceBrowser: OcaNetworkAdvertisingServiceBrowser, @unchecked Sendable {
  private let _serviceType: OcaNetworkAdvertisingServiceType
  private let _browseResults = AsyncChannel<OcaNetworkAdvertisingServiceBrowserResult>()
  private let _browseSource: DispatchSourceRead

  final class BrowseContext: @unchecked Sendable {
    var browser: OcaDNSServiceBrowser?

    init(browser: OcaDNSServiceBrowser?) {
      self.browser = browser
    }
  }

  public init(serviceType: OcaNetworkAdvertisingServiceType) throws {
    _serviceType = serviceType

    var sdRef: DNSServiceRef?

    let browseContext = BrowseContext(browser: nil)
    let context = Unmanaged.passRetained(browseContext).toOpaque()

    let error = DNSServiceBrowse(
      &sdRef,
      0, // flags
      UInt32(kDNSServiceInterfaceIndexAny),
      serviceType.rawValue,
      nil, // domain (nil means .local)
      DNSServiceBrowseBlock_Thunk,
      context
    )

    guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let sdRef else {
      Unmanaged<BrowseContext>.fromOpaque(context).release()
      throw Ocp1Error.notImplemented
    }

    let source = DispatchSource.makeReadSource(
      fileDescriptor: DNSServiceRefSockFD(sdRef),
      queue: DispatchQueue(label: "com.padl.SwiftOCA.DNSServiceBrowse")
    )

    source.setEventHandler { DNSServiceProcessResult(sdRef) }
    source.setCancelHandler { DNSServiceRefDeallocate(sdRef) }

    _browseSource = source

    // Update context with self after initialization
    browseContext.browser = self
  }

  public nonisolated var browseResults: AnyAsyncSequence<OcaNetworkAdvertisingServiceBrowserResult> {
    _browseResults.eraseToAnyAsyncSequence()
  }

  public func start() async throws {
    _browseSource.resume()
  }

  public func stop() throws {
    _browseSource.cancel()
    _browseResults.finish()
  }

  deinit {
    _browseSource.cancel()
  }

  fileprivate func _handleServiceChange(
    isAdd: Bool,
    name: String,
    serviceType: OcaNetworkAdvertisingServiceType,
    domain: String,
    interfaceIndex: UInt32
  ) {
    let serviceInfo = _DNSServiceInfo(
      name: name,
      serviceType: serviceType,
      domain: domain,
      interfaceIndex: interfaceIndex
    )

    Task {
      await _browseResults.send(isAdd ? .added(serviceInfo) : .removed(serviceInfo))
    }
  }
}

@_cdecl("DNSServiceBrowseBlock_Thunk")
private func DNSServiceBrowseBlock_Thunk(
  _ sdRef: DNSServiceRef?,
  _ flags: DNSServiceFlags,
  _ interfaceIndex: UInt32,
  _ error: DNSServiceErrorType,
  _ serviceName: UnsafePointer<CChar>?,
  _ regtype: UnsafePointer<CChar>?,
  _ replyDomain: UnsafePointer<CChar>?,
  _ context: UnsafeMutableRawPointer?
) {
  guard let context, let serviceName, let regtype, let replyDomain else { return }

  let browseContext = Unmanaged<OcaDNSServiceBrowser.BrowseContext>.fromOpaque(context)
    .takeUnretainedValue()

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
    // Log error but continue browsing
    return
  }

  guard let browser = browseContext.browser else { return }

  let name = String(cString: serviceName)
  let serviceTypeString = String(cString: regtype)
  let domain = String(cString: replyDomain)

  guard let serviceType = OcaNetworkAdvertisingServiceType(rawValue: serviceTypeString) else {
    return
  }

  let isAdd = (flags & DNSServiceFlags(kDNSServiceFlagsAdd)) != 0

  Task {
    await browser._handleServiceChange(
      isAdd: isAdd,
      name: name,
      serviceType: serviceType,
      domain: domain,
      interfaceIndex: interfaceIndex
    )
  }
}

#endif
