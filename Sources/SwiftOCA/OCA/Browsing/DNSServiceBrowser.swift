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
import SocketAddress

/// A private class that represents a discovered DNS-SD service
private final class _DNSServiceInfo: OcaNetworkAdvertisingServiceInfo, @unchecked Sendable {
  var service: OcaNetworkAdvertisingService { .mDNS_DNSSD }
  let serviceType: OcaNetworkAdvertisingServiceType
  let name: String
  let domain: String

  struct ResolutionInfo {
    var hostname: String!
    var port: UInt16!
    var addresses: [Data] = []
    var txtRecords: [String: String] = [:]
  }

  // Context objects for passing to C callbacks
  final class ResolveContext: @unchecked Sendable {
    let channel: AsyncStream<ResolutionInfo>.Continuation
    let serviceInfo: _DNSServiceInfo
    var source: DispatchSourceRead?

    init(channel: AsyncStream<ResolutionInfo>.Continuation, serviceInfo: _DNSServiceInfo) {
      self.channel = channel
      self.serviceInfo = serviceInfo
    }
  }

  // resolved name and addresses, set (semi-)atomically after resolve() called
  // they are indexed by interface address, which may be sparse (hence a dictionary)
  let _resolutionInfo: Mutex<[Int: ResolutionInfo]> = .init([:])

  init(
    name: String,
    serviceType: OcaNetworkAdvertisingServiceType,
    domain: String
  ) {
    self.name = name
    self.serviceType = serviceType
    self.domain = domain
  }

  // currently we only use the first resolution info, and address, sorted by interface
  // number but in the future we should try to connect to all resolution infos and
  // addresses and pick the first and/or least latent one
  private var _currentResolutionInfo: (Int, ResolutionInfo) {
    get throws {
      guard let resolutionInfo = _resolutionInfo.withLock({ resolutionInfo in
        resolutionInfo.sorted(by: { $0.key < $1.key }).first
      }) else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return resolutionInfo
    }
  }

  var hostname: String {
    get throws {
      guard let hostname = try _currentResolutionInfo.1.hostname else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return hostname
    }
  }

  var port: UInt16 {
    get throws {
      guard let port = try _currentResolutionInfo.1.port else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return port
    }
  }

  var addresses: [Data] {
    get throws {
      let addresses = try _currentResolutionInfo.1.addresses
      guard !addresses.isEmpty else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return addresses
    }
  }

  var txtRecords: [String: String] {
    get throws {
      try _currentResolutionInfo.1.txtRecords
    }
  }

  func resolve() async throws {
    // do nothing if already resolved
    guard _resolutionInfo.criticalValue.isEmpty else { return }

    // Use kDNSServiceInterfaceIndexAny to resolve on all interfaces
    // The callbacks will tell us which interfaces have results
    let stream = _resolveService(interfaceIndex: UInt32(kDNSServiceInterfaceIndexAny))

    // Collect at least one result from the stream
    var hasResults = false
    for await _ in stream {
      hasResults = true
      // Results are already stored in _resolutionInfo by the callback
      // We can break after getting the first result since they're all for the same service
      break
    }

    guard hasResults else {
      throw Ocp1Error.serviceResolutionFailed
    }

    // Now resolve the hostname to IP addresses, just using the first resolution info for now
    try await _resolveAddresses(interfaceIndex: UInt32(_currentResolutionInfo.0))
  }

  private func _resolveService(interfaceIndex: UInt32) -> AsyncStream<ResolutionInfo> {
    AsyncStream { continuation in
      var sdRef: DNSServiceRef?

      let resolveContext = ResolveContext(channel: continuation, serviceInfo: self)
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
        continuation.finish()
        return
      }

      let source = DispatchSource.makeReadSource(
        fileDescriptor: DNSServiceRefSockFD(sdRef),
        queue: DispatchQueue(label: "com.padl.SwiftOCA.DNSServiceResolve")
      )

      source.setEventHandler { DNSServiceProcessResult(sdRef) }
      source.setCancelHandler {
        DNSServiceRefDeallocate(sdRef)
        Unmanaged<ResolveContext>.fromOpaque(context).release()
      }

      continuation.onTermination = { _ in
        source.cancel()
      }

      resolveContext.source = source
      source.resume()
    }
  }

  private func _resolveAddresses(interfaceIndex: UInt32) async throws {
    try _resolutionInfo.withLock { resolutionInfo in
      guard let hostname = resolutionInfo[Int(interfaceIndex)]?.hostname,
            let port = resolutionInfo[Int(interfaceIndex)]?.port
      else {
        throw Ocp1Error.serviceResolutionFailed
      }

      var hints = addrinfo()
      hints.ai_family = AF_UNSPEC // Allow both IPv4 and IPv6
      hints.ai_socktype = serviceType == .udp ? SOCK_DGRAM : SOCK_STREAM

      var result: UnsafeMutablePointer<addrinfo>?
      defer { if let result { freeaddrinfo(result) } }

      let error = getaddrinfo(hostname, nil, &hints, &result)
      guard error == 0, let result else {
        throw Ocp1Error.serviceResolutionFailed
      }

      let addresses = sequence(first: result, next: { $0.pointee.ai_next })
        .compactMap { (addrPtr: UnsafeMutablePointer<addrinfo>) -> Data? in
          let addrInfo = addrPtr.pointee
          guard addrInfo.ai_addr != nil else { return nil }

          let bytes = UnsafeRawBufferPointer(
            start: addrInfo.ai_addr,
            count: Int(addrInfo.ai_addrlen)
          )
          guard var sockAddr = try? AnySocketAddress(bytes: Array(bytes)) else { return nil }

          switch sockAddr.family {
          case sa_family_t(AF_INET):
            sockAddr.withMutableSockAddr {
              $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_port = port.bigEndian
              }
            }
          case sa_family_t(AF_INET6):
            sockAddr.withMutableSockAddr {
              $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee.sin6_port = port.bigEndian
              }
            }
          case sa_family_t(AF_LOCAL):
            break
          default:
            return nil
          }

          return Data(sockAddr.bytes)
        }

      resolutionInfo[Int(interfaceIndex)]!.addresses = Array(addresses)
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

// Helper function to parse DNS-SD TXT records
private func parseTxtRecords(txtLen: UInt16, txtRecord: UnsafePointer<UInt8>?) -> [String: String] {
  var txtRecords: [String: String] = [:]

  guard txtLen > 0, let txtRecord else { return txtRecords }

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

  return txtRecords
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
    .takeUnretainedValue()

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
    resolveContext.channel.finish()
    return
  }

  guard let hosttarget else {
    resolveContext.channel.finish()
    return
  }

  let hostname = String(cString: hosttarget)
  let hostPort = UInt16(bigEndian: port)
  let txtRecords = parseTxtRecords(txtLen: txtLen, txtRecord: txtRecord)

  let resolutionInfo = _DNSServiceInfo.ResolutionInfo(
    hostname: hostname,
    port: hostPort,
    addresses: [],
    txtRecords: txtRecords
  )

  // Store result in the service's resolution info dictionary using the interface index from
  // callback
  resolveContext.serviceInfo._resolutionInfo.withLock {
    $0[Int(interfaceIndex)] = resolutionInfo
  }

  // Send result through the channel
  resolveContext.channel.yield(resolutionInfo)
}

/// A DNS-SD browser implementation using dns_sd.h
public final class OcaDNSServiceBrowser: OcaNetworkAdvertisingServiceBrowser, @unchecked Sendable {
  private let _serviceType: OcaNetworkAdvertisingServiceType
  private let _browseResultsContinuation: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>
    .Continuation
  private let _browseSource: DispatchSourceRead
  private let _discoveredServices: Mutex<Set<String>> = .init(Set())

  public let browseResults: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>

  final class BrowseContext: @unchecked Sendable {
    var browser: OcaDNSServiceBrowser?

    init(browser: OcaDNSServiceBrowser?) {
      self.browser = browser
    }
  }

  public init(serviceType: OcaNetworkAdvertisingServiceType) throws {
    _serviceType = serviceType

    let (stream, continuation) = AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>.makeStream()
    browseResults = stream
    _browseResultsContinuation = continuation

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

  public func start() async throws {
    _browseSource.resume()
  }

  public func stop() throws {
    _browseSource.cancel()
    _browseResultsContinuation.finish()
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
    // Create unique identifier for the service (same as OcaNetworkAdvertisingServiceInfo.id)
    let serviceId = "\(name).\(serviceType.rawValue)\(domain)"

    let shouldNotify = _discoveredServices.withLock { discoveredServices in
      if isAdd {
        // Only yield .added if this is the first time we see this service
        discoveredServices.insert(serviceId).inserted
      } else {
        // Only yield .removed if we actually had this service
        discoveredServices.remove(serviceId) != nil
      }
    }

    if shouldNotify {
      let serviceInfo = _DNSServiceInfo(
        name: name,
        serviceType: serviceType,
        domain: domain
      )

      _browseResultsContinuation.yield(isAdd ? .added(serviceInfo) : .removed(serviceInfo))
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

  browser._handleServiceChange(
    isAdd: (flags & DNSServiceFlags(kDNSServiceFlagsAdd)) != 0,
    name: name,
    serviceType: serviceType,
    domain: domain,
    interfaceIndex: interfaceIndex
  )
}

#endif
