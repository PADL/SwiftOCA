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
@preconcurrency import Dispatch
import dnssd
import SocketAddress
import Synchronization

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

  /// Long enough for a query to be sent again twice; Avahi gives up after as long.
  private static let _resolveTimeout = Duration.seconds(5)

  func resolve() async throws {
    // do nothing if already resolved, which a service without addresses is not
    guard (try? addresses) == nil else { return }

    // Use kDNSServiceInterfaceIndexAny to resolve on all interfaces
    // The callbacks will tell us which interfaces have results
    let stream = _resolveService(interfaceIndex: UInt32(kDNSServiceInterfaceIndexAny))

    // One result is enough, as they are all for the same service, and the callback has
    // stored it in _resolutionInfo. mDNSResponder never gives up on a resolve by itself.
    let resolution = try? await withThrowingTimeout(of: Self._resolveTimeout, clock: .continuous) {
      await stream.first { _ in true }
    }

    guard resolution != nil else {
      throw Ocp1Error.serviceResolutionFailed
    }

    // Now resolve the hostname to IP addresses, just using the first resolution info for now
    try await _resolveAddresses(interfaceIndex: UInt32(_currentResolutionInfo.0))
  }

  private func _resolveService(interfaceIndex: UInt32) -> AsyncStream<DNSServiceResolution> {
    _resolveDNSService(
      name: name,
      regType: serviceType.rawValue,
      domain: domain,
      interfaceIndex: interfaceIndex
    ) { [self] resolution in
      // Store result in the service's resolution info dictionary using the interface index
      // from callback
      _resolutionInfo.withLock {
        $0[Int(resolution.interfaceIndex)] = ResolutionInfo(
          hostname: resolution.hostname,
          port: resolution.port,
          addresses: [],
          txtRecords: resolution.txtRecords
        )
      }
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
            sockAddr.withMutableSockAddr { sa, _ in
              sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                sin.pointee.sin_port = port.bigEndian
              }
            }
          case sa_family_t(AF_INET6):
            sockAddr.withMutableSockAddr { sa, _ in
              sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                sin6.pointee.sin6_port = port.bigEndian
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

// Context object for passing to the resolve callback
private final class _DNSServiceResolveContext: @unchecked Sendable {
  let channel: AsyncStream<DNSServiceResolution>.Continuation
  /// Called from the callback, before the resolution is sent through the channel.
  let onResult: (@Sendable (DNSServiceResolution) -> ())?
  var source: DispatchSourceRead?

  init(
    channel: AsyncStream<DNSServiceResolution>.Continuation,
    onResult: (@Sendable (DNSServiceResolution) -> ())?
  ) {
    self.channel = channel
    self.onResult = onResult
  }
}

private func _resolveDNSService(
  name: String,
  regType: String,
  domain: String,
  interfaceIndex: UInt32,
  onResult: (@Sendable (DNSServiceResolution) -> ())? = nil
) -> AsyncStream<DNSServiceResolution> {
  AsyncStream { continuation in
    var sdRef: DNSServiceRef?

    let resolveContext = _DNSServiceResolveContext(channel: continuation, onResult: onResult)
    let context = Unmanaged.passRetained(resolveContext).toOpaque()

    let error = DNSServiceResolve(
      &sdRef,
      0, // flags
      interfaceIndex,
      name,
      regType,
      domain,
      DNSServiceResolveBlock_Thunk,
      context
    )

    guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let sdRef else {
      Unmanaged<_DNSServiceResolveContext>.fromOpaque(context).release()
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
      Unmanaged<_DNSServiceResolveContext>.fromOpaque(context).release()
    }

    continuation.onTermination = { _ in
      source.cancel()
    }

    resolveContext.source = source
    source.resume()
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

  let resolveContext = Unmanaged<_DNSServiceResolveContext>.fromOpaque(context)
    .takeUnretainedValue()

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
    resolveContext.channel.finish()
    return
  }

  guard let hosttarget else {
    resolveContext.channel.finish()
    return
  }

  let resolution = DNSServiceResolution(
    interfaceIndex: interfaceIndex,
    hostname: String(cString: hosttarget),
    port: UInt16(bigEndian: port),
    txtRecords: DNSServiceTXTRecord.decode(UnsafeBufferPointer(start: txtRecord, count: Int(txtLen)))
  )

  resolveContext.onResult?(resolution)

  // Send result through the channel
  resolveContext.channel.yield(resolution)
}

// Context object for passing to the browse callback
private final class _DNSServiceBrowseContext: @unchecked Sendable {
  var handler: (@Sendable (DNSServiceBrowseResult) -> ())?
}

/// Starts browsing and returns the source that processes its results once resumed.
/// Cancelling the source ends the browse and then calls `onCancel`. `onFailure` is
/// called if the connection to the responder fails, as it does when the responder is
/// restarted. The caller owns the retained `context`, which must outlive the source.
private func _makeDNSServiceBrowseSource(
  regType: String,
  domain: String?,
  context: UnsafeMutableRawPointer,
  onFailure: (@Sendable () -> ())? = nil,
  onCancel: (@Sendable () -> ())? = nil
) -> DispatchSourceRead? {
  var sdRef: DNSServiceRef?

  let error = DNSServiceBrowse(
    &sdRef,
    0, // flags
    UInt32(kDNSServiceInterfaceIndexAny),
    regType,
    domain, // domain (nil means .local)
    DNSServiceBrowseBlock_Thunk,
    context
  )

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let sdRef else { return nil }

  let source = DispatchSource.makeReadSource(
    fileDescriptor: DNSServiceRefSockFD(sdRef),
    queue: DispatchQueue(label: "com.padl.SwiftOCA.DNSServiceBrowse")
  )

  source.setEventHandler {
    if DNSServiceProcessResult(sdRef) != DNSServiceErrorType(kDNSServiceErr_NoError) {
      onFailure?()
    }
  }
  source.setCancelHandler {
    DNSServiceRefDeallocate(sdRef)
    onCancel?()
  }

  return source
}

/// A service instance that a browse found, or that it had found and has now lost.
@_spi(SwiftOCAPrivate)
public struct DNSServiceBrowseResult: Sendable, Hashable {
  /// False when the service has gone away.
  public let isAdded: Bool
  public let name: String
  public let regType: String
  public let domain: String
  public let interfaceIndex: UInt32
}

/// Where a service instance can be reached, and its TXT record.
@_spi(SwiftOCAPrivate)
public struct DNSServiceResolution: Sendable, Hashable {
  /// The interface the answer arrived on; a service may answer on several.
  public let interfaceIndex: UInt32
  public let hostname: String
  /// In host byte order.
  public let port: UInt16
  public let txtRecords: [String: String]
}

/// DNS-SD browsing and resolution for any service type, on the dns_sd calls the OCA
/// browser below is built from.
@_spi(SwiftOCAPrivate)
public enum DNSServiceDiscovery {
  /// Browses for instances of `regType` (such as `_http._tcp`) until the stream's
  /// consumer stops iterating. A nil `domain` is the default browse domains. The stream
  /// ends by itself if the connection to the responder fails; browse again to recover.
  public static func browse(
    regType: String,
    domain: String? = nil
  ) throws -> AsyncStream<DNSServiceBrowseResult> {
    let (stream, continuation) = AsyncStream<DNSServiceBrowseResult>.makeStream()

    let browseContext = _DNSServiceBrowseContext()
    browseContext.handler = { continuation.yield($0) }
    let context = Unmanaged.passRetained(browseContext)

    guard let source = _makeDNSServiceBrowseSource(
      regType: regType,
      domain: domain,
      context: context.toOpaque(),
      onFailure: { continuation.finish() },
      onCancel: { context.release() }
    ) else {
      context.release()
      throw Ocp1Error.serviceBrowsingUnavailable
    }

    continuation.onTermination = { _ in source.cancel() }
    source.resume()

    return stream
  }

  /// Resolves an instance a browse found, yielding an answer per interface until the
  /// consumer stops iterating. The stream ends without an answer if resolution fails.
  public static func resolve(
    name: String,
    regType: String,
    domain: String,
    interfaceIndex: UInt32 = UInt32(kDNSServiceInterfaceIndexAny)
  ) -> AsyncStream<DNSServiceResolution> {
    _resolveDNSService(name: name, regType: regType, domain: domain, interfaceIndex: interfaceIndex)
  }

  /// The addresses of `hostname` as numeric host strings, IPv4 first. They come from
  /// DNSServiceGetAddrInfo where the dns_sd library has it, so that a `.local` name needs
  /// no resolver plug-in, and from the system resolver where it does not or finds none.
  public static func addresses(
    of hostname: String,
    interfaceIndex: UInt32 = UInt32(kDNSServiceInterfaceIndexAny),
    timeout: Duration = .seconds(3)
  ) async -> [String] {
    var addresses = [String]()
    if let stream = _getDNSServiceAddrInfo(hostname: hostname, interfaceIndex: interfaceIndex) {
      let deadline = Task {
        try await Task.sleep(for: timeout)
        stream.continuation.finish()
      }
      for await address in stream.stream where !addresses.contains(address) {
        addresses.append(address)
      }
      deadline.cancel()
    }
    if addresses.isEmpty {
      addresses = _systemAddresses(of: hostname)
    }
    // a stable partition: IPv6 presentation addresses are the ones with a colon
    return addresses.filter { !$0.contains(":") } + addresses.filter { $0.contains(":") }
  }
}

// MARK: - address resolution

// DNSServiceGetAddrInfo and its reply, declared here because a dns_sd library may lack
// them (Avahi's does), in which case neither its header nor a direct call would build.
typealias _DNSServiceGetAddrInfoReply = @convention(c) (
  DNSServiceRef?,
  DNSServiceFlags,
  UInt32,
  DNSServiceErrorType,
  UnsafePointer<CChar>?,
  UnsafePointer<sockaddr>?,
  UInt32,
  UnsafeMutableRawPointer?
) -> ()

private typealias _DNSServiceGetAddrInfo = @convention(c) (
  UnsafeMutablePointer<DNSServiceRef?>?,
  DNSServiceFlags,
  UInt32,
  UInt32,
  UnsafePointer<CChar>?,
  _DNSServiceGetAddrInfoReply?,
  UnsafeMutableRawPointer?
) -> DNSServiceErrorType

/// The library's DNSServiceGetAddrInfo, nil where it has none.
private let _dnsServiceGetAddrInfo: _DNSServiceGetAddrInfo? = {
  #if canImport(Darwin)
  let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
  #else
  let defaultHandle: UnsafeMutableRawPointer? = nil // RTLD_DEFAULT
  #endif
  guard let symbol = dlsym(defaultHandle, "DNSServiceGetAddrInfo") else { return nil }
  return unsafeBitCast(symbol, to: _DNSServiceGetAddrInfo.self)
}()

final class _DNSServiceAddrInfoContext: @unchecked Sendable {
  let channel: AsyncStream<String>.Continuation

  init(channel: AsyncStream<String>.Continuation) {
    self.channel = channel
  }
}

/// Starts DNSServiceGetAddrInfo for both address families; nil where the library has no
/// such call or refuses it. The stream ends with the first complete set of answers.
private func _getDNSServiceAddrInfo(
  hostname: String,
  interfaceIndex: UInt32
) -> (stream: AsyncStream<String>, continuation: AsyncStream<String>.Continuation)? {
  guard let getAddrInfo = _dnsServiceGetAddrInfo else { return nil }

  let (stream, continuation) = AsyncStream<String>.makeStream()
  let context = Unmanaged.passRetained(_DNSServiceAddrInfoContext(channel: continuation))

  var sdRef: DNSServiceRef?
  // a zero protocol asks for the address families the host can route
  let error = getAddrInfo(
    &sdRef,
    0,
    interfaceIndex,
    0,
    hostname,
    DNSServiceGetAddrInfoBlock_Thunk,
    context.toOpaque()
  )

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let sdRef else {
    context.release()
    return nil
  }

  let source = DispatchSource.makeReadSource(
    fileDescriptor: DNSServiceRefSockFD(sdRef),
    queue: DispatchQueue(label: "com.padl.SwiftOCA.DNSServiceGetAddrInfo")
  )

  source.setEventHandler { DNSServiceProcessResult(sdRef) }
  source.setCancelHandler {
    DNSServiceRefDeallocate(sdRef)
    context.release()
  }

  continuation.onTermination = { _ in source.cancel() }
  source.resume()

  return (stream, continuation)
}

let DNSServiceGetAddrInfoBlock_Thunk: _DNSServiceGetAddrInfoReply = {
  _, flags, _, error, _, address, _, context in
  guard let context else { return }

  let addrInfoContext = Unmanaged<_DNSServiceAddrInfoContext>.fromOpaque(context)
    .takeUnretainedValue()

  // an error here is one address family having no record; the other may yet answer
  guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else { return }

  if (flags & DNSServiceFlags(kDNSServiceFlagsAdd)) != 0, let address,
     let host = _numericHost(address)
  {
    addrInfoContext.channel.yield(host)
  }

  if (flags & DNSServiceFlags(kDNSServiceFlagsMoreComing)) == 0 {
    addrInfoContext.channel.finish()
  }
}

func _numericHost(_ address: UnsafePointer<sockaddr>) -> String? {
  let length: Int
  switch Int32(address.pointee.sa_family) {
  case AF_INET: length = MemoryLayout<sockaddr_in>.size
  case AF_INET6: length = MemoryLayout<sockaddr_in6>.size
  default: return nil
  }
  var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
  guard getnameinfo(address, socklen_t(length), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
  else { return nil }
  return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

private func _systemAddresses(of hostname: String) -> [String] {
  var hints = addrinfo()
  hints.ai_family = AF_UNSPEC
  hints.ai_socktype = SOCK_STREAM

  var result: UnsafeMutablePointer<addrinfo>?
  defer { if let result { freeaddrinfo(result) } }
  guard getaddrinfo(hostname, nil, &hints, &result) == 0, let result else { return [] }

  var addresses = [String]()
  for info in sequence(first: result, next: { $0.pointee.ai_next }) {
    guard let address = info.pointee.ai_addr, let host = _numericHost(address),
          !addresses.contains(host) else { continue }
    addresses.append(host)
  }
  return addresses
}

/// A DNS-SD browser implementation using dns_sd.h
public final class OcaDNSServiceBrowser: OcaNetworkAdvertisingServiceBrowser, @unchecked Sendable {
  private let _serviceType: OcaNetworkAdvertisingServiceType
  private let _browseResultsContinuation: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>
    .Continuation
  private let _browseSource: DispatchSourceRead
  private let _discoveredServices: Mutex<Set<String>> = .init(Set())

  public let browseResults: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>

  public init(serviceType: OcaNetworkAdvertisingServiceType) throws {
    _serviceType = serviceType

    let (stream, continuation) = AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>.makeStream()
    browseResults = stream
    _browseResultsContinuation = continuation

    let browseContext = _DNSServiceBrowseContext()
    let context = Unmanaged.passRetained(browseContext).toOpaque()

    guard let source = _makeDNSServiceBrowseSource(
      regType: serviceType.rawValue,
      domain: nil,
      context: context
    ) else {
      Unmanaged<_DNSServiceBrowseContext>.fromOpaque(context).release()
      throw Ocp1Error.serviceBrowsingUnavailable
    }

    _browseSource = source

    // Update context with self after initialization
    browseContext.handler = { [self] result in
      // a service type this browser does not know is not one of ours
      guard let serviceType = OcaNetworkAdvertisingServiceType(rawValue: result.regType) else {
        return
      }

      _handleServiceChange(
        isAdd: result.isAdded,
        name: result.name,
        serviceType: serviceType,
        domain: result.domain,
        interfaceIndex: result.interfaceIndex
      )
    }
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
    // FIXME: we probably want to notify if the address changes, should we emit and remove
    // then an add? or add a new updated type?
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

  let browseContext = Unmanaged<_DNSServiceBrowseContext>.fromOpaque(context)
    .takeUnretainedValue()

  guard error == DNSServiceErrorType(kDNSServiceErr_NoError) else {
    // Log error but continue browsing
    return
  }

  guard let handler = browseContext.handler else { return }

  handler(DNSServiceBrowseResult(
    isAdded: (flags & DNSServiceFlags(kDNSServiceFlagsAdd)) != 0,
    name: String(cString: serviceName),
    regType: String(cString: regtype),
    domain: String(cString: replyDomain),
    interfaceIndex: interfaceIndex
  ))
}

#endif
