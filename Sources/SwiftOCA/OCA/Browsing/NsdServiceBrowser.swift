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

#if os(Android)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Android
import AndroidNetworkServiceDiscovery
import SocketAddress
import Synchronization

// Android never reports a domain, and NsdServiceInfo.getServiceType() is
// inconsistent across API levels about leading and trailing dots. Both matter
// more than they look: `OcaNetworkAdvertisingServiceInfo.id` is
// "\(name).\(serviceType.rawValue)\(domain)" and is what the connection broker
// uses as device identity, so a mismatch between the string seen at .added and
// the one seen at .removed leaves devices stranded in the broker forever.
private let OcaNsdDomain = "local."

private extension OcaNetworkAdvertisingServiceType {
  /// The service type as `NsdManager.discoverServices` wants it.
  ///
  /// The enum rawValues carry a trailing dot ("_oca._tcp."); Android rejects
  /// that form.
  var nsdServiceType: String {
    rawValue._trimmingDots
  }

  /// Recover the case from whatever `getServiceType()` chose to return.
  ///
  /// Observed variants include "_oca._tcp", "_oca._tcp.", "._oca._tcp" and
  /// forms with ".local." appended.
  static func from(nsdServiceType: String) -> Self? {
    var normalized = nsdServiceType
    if let localRange = normalized.range(of: ".local", options: [.caseInsensitive, .backwards]) {
      normalized = String(normalized[normalized.startIndex..<localRange.lowerBound])
    }
    let trimmed = normalized._trimmingDots.lowercased()
    return Self.allCases.first { $0 != .none && $0.nsdServiceType.lowercased() == trimmed }
  }
}

private extension String {
  /// Leading and trailing dots removed.
  ///
  /// Hand-rolled because `CharacterSet` lives in full Foundation, which this
  /// module does not necessarily import.
  var _trimmingDots: String {
    var slice = Substring(self)
    while slice.first == "." { slice = slice.dropFirst() }
    while slice.last == "." { slice = slice.dropLast() }
    return String(slice)
  }
}

/// A service browser backed by Android's `NsdManager`.
///
/// `AndroidNsd.configure(context:)` must have been called first; without a
/// `Context` there is no way to reach `NsdManager`.
public final class OcaNsdServiceBrowser: OcaNetworkAdvertisingServiceBrowser, @unchecked Sendable {
  private let _serviceType: OcaNetworkAdvertisingServiceType
  private let _browseResultsContinuation: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>
    .Continuation
  // Assigned once `self` is available; see init.
  private var _listener: AndroidNsdDiscoveryListener!
  private let _started: Mutex<Bool> = .init(false)

  public let browseResults: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>

  public init(serviceType: OcaNetworkAdvertisingServiceType) throws {
    guard AndroidNsd.isConfigured else {
      throw Ocp1Error.notImplemented
    }

    _serviceType = serviceType

    let (stream, continuation) = AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>.makeStream()
    browseResults = stream
    _browseResultsContinuation = continuation

    // NB: the Java listener owns this closure, so `self` is captured weakly --
    // a strong capture would keep the browser alive for as long as NsdManager
    // holds the listener. This has to happen after every stored property has a
    // value, which is why _listener is a var: capturing a local `var browser`
    // weakly and assigning it afterwards does *not* work, because a weak
    // capture snapshots the value at closure creation (nil), not the variable.
    _listener = AndroidNsdDiscoveryListener { [weak self] event in
      self?._onDiscoveryEvent(event)
    }
  }

  /// swift-java models the Java class and the interface it implements as
  /// unrelated Swift types, so the relationship has to be re-stated here.
  private var _listenerInterface: NsdManager.DiscoveryListener? {
    _listener.as(NsdManager.DiscoveryListener.self)
  }

  /// Maps NSD's discovery callbacks straight onto the browse stream.
  ///
  /// Deliberately stateless: no set of already-seen services is kept. A repeat
  /// `.added` is meaningful rather than redundant -- the broker uses it to spot
  /// an address change and migrate the live connection (see
  /// `_onBrowserDeviceAdded`) -- so filtering duplicates here would suppress
  /// exactly the signal it wants. NsdManager already coalesces discovery per
  /// session, so duplicates are rare in any case.
  private func _onDiscoveryEvent(_ event: AndroidNsdDiscoveryEvent) {
    switch event {
    case let .found(descriptor):
      _yield(descriptor, isAdd: true)
    case let .lost(descriptor):
      _yield(descriptor, isAdd: false)
    case .started, .stopped:
      break
    case .failed:
      // Discovery is dead; end the sequence rather than leave the broker
      // waiting on a stream that will never produce anything.
      _browseResultsContinuation.finish()
    }
  }

  private func _yield(_ descriptor: AndroidNsdServiceDescriptor, isAdd: Bool) {
    // Trust the type we asked for over the one echoed back: Android's rendering
    // of it varies by API level, and this string ends up in the device identity.
    let resolvedType = OcaNetworkAdvertisingServiceType
      .from(nsdServiceType: descriptor.serviceType) ?? _serviceType
    guard resolvedType == _serviceType else { return }

    let serviceInfo = _NsdServiceInfo(
      name: descriptor.name,
      serviceType: _serviceType,
      domain: OcaNsdDomain
    )
    _browseResultsContinuation.yield(isAdd ? .added(serviceInfo) : .removed(serviceInfo))
  }

  public func start() async throws {
    let alreadyStarted = _started.withLock { started -> Bool in
      defer { started = true }
      return started
    }
    guard !alreadyStarted else { return }

    let nsdManager = try AndroidNsd.nsdManager
    nsdManager.discoverServices(
      _serviceType.nsdServiceType,
      AndroidNsd.protocolDnsSd,
      _listenerInterface
    )
  }

  public func stop() throws {
    let wasStarted = _started.withLock { started -> Bool in
      defer { started = false }
      return started
    }
    if wasStarted {
      try? AndroidNsd.nsdManager.stopServiceDiscovery(_listenerInterface)
    }
    _browseResultsContinuation.finish()
  }

  deinit {
    try? stop()
  }
}

/// A service discovered by `NsdManager`, resolved on demand.
private final class _NsdServiceInfo: OcaNetworkAdvertisingServiceInfo, @unchecked Sendable {
  var service: OcaNetworkAdvertisingService { .mDNS_DNSSD }
  let serviceType: OcaNetworkAdvertisingServiceType
  let name: String
  let domain: String

  private let _resolution: Mutex<AndroidNsdResolution?> = .init(nil)

  init(
    name: String,
    serviceType: OcaNetworkAdvertisingServiceType,
    domain: String
  ) {
    self.name = name
    self.serviceType = serviceType
    self.domain = domain
  }

  private var _resolved: AndroidNsdResolution {
    get throws {
      guard let resolution = _resolution.withLock({ $0 }) else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return resolution
    }
  }

  var hostname: String {
    get throws { try _resolved.hostname }
  }

  var port: UInt16 {
    get throws { try _resolved.port }
  }

  /// Socket addresses, as `sockaddr` bytes.
  ///
  /// Android hands back bare `InetAddress`es with no family or port, so unlike
  /// the Darwin and dnssd browsers -- which receive real sockaddrs -- these have
  /// to be synthesized from the presentation form plus the resolved port.
  var addresses: [Data] {
    get throws {
      let resolution = try _resolved
      let port = resolution.port

      let addresses: [Data] = resolution.addresses.compactMap { presentation in
        if presentation.contains(":") {
          guard var sin6 = try? sockaddr_in6(
            family: sa_family_t(AF_INET6),
            presentationAddress: "[\(presentation)]:\(port)"
          ) else { return nil }
          return withUnsafeBytes(of: &sin6) { Data($0) }
        } else {
          guard var sin = try? sockaddr_in(
            family: sa_family_t(AF_INET),
            presentationAddress: "\(presentation):\(port)"
          ) else { return nil }
          return withUnsafeBytes(of: &sin) { Data($0) }
        }
      }

      guard !addresses.isEmpty else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return addresses
    }
  }

  var txtRecords: [String: String] {
    get throws { try _resolved.txtRecords }
  }

  func resolve() async throws {
    // Do nothing if already resolved, matching OcaDNSServiceBrowser.
    guard _resolution.withLock({ $0 }) == nil else { return }

    let resolution = try await _register()
    _resolution.withLock { $0 = resolution }
  }

  /// Resolves via `registerServiceInfoCallback`.
  ///
  /// Deliberately not `resolveService()`: that permits only one in-flight
  /// resolve per NsdManager and fails concurrent callers with
  /// FAILURE_ALREADY_ACTIVE, which the broker would hit as soon as a second
  /// device appeared.
  private func _register() async throws -> AndroidNsdResolution {
    let nsdManager = try AndroidNsd.nsdManager
    let executor = try AndroidNsd.mainExecutor

    // A stream rather than a checked continuation: the callback fires
    // repeatedly (onServiceUpdated on every change), so a continuation would
    // need resume-once bookkeeping and a box to hold the callback for
    // unregistration. Taking the first element and unregistering in `defer`
    // covers cancellation too -- AsyncStream iteration ends when the task is
    // cancelled.
    let (events, continuation) = AsyncStream<AndroidNsdServiceInfoEvent>.makeStream()
    let callback = AndroidNsdServiceInfoCallback { continuation.yield($0) }
    let callbackInterface = callback.as(NsdManager.ServiceInfoCallback.self)

    let query = NsdServiceInfo()
    query.setServiceName(name)
    query.setServiceType(serviceType.nsdServiceType)

    nsdManager.registerServiceInfoCallback(query, executor, callbackInterface)
    defer {
      // NsdManager keeps delivering until told otherwise.
      try? AndroidNsd.nsdManager.unregisterServiceInfoCallback(callbackInterface)
      continuation.finish()
    }

    for await event in events {
      switch event {
      case let .updated(resolution):
        return resolution
      case .lost:
        throw Ocp1Error.serviceResolutionFailed
      case let .failed(error):
        throw error
      case .unregistered:
        continue
      }
    }

    throw Ocp1Error.serviceResolutionFailed
  }

  nonisolated static func == (lhs: _NsdServiceInfo, rhs: _NsdServiceInfo) -> Bool {
    lhs.name == rhs.name && lhs.serviceType == rhs.serviceType && lhs.domain == rhs.domain
  }

  nonisolated func hash(into hasher: inout Hasher) {
    name.hash(into: &hasher)
    serviceType.hash(into: &hasher)
    domain.hash(into: &hasher)
  }
}

#endif
