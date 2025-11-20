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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import AsyncAlgorithms
import AsyncExtensions
import SocketAddress

/// A protocol representing information about a network advertising service discovered on the
/// network.
///
/// This protocol provides a portable abstraction over platform-specific network service discovery
/// mechanisms (such as Bonjour/mDNS on macOS/iOS, or other advertising protocols on different
/// platforms).
/// It encapsulates the details of an OCA (Open Control Architecture) device or service that has
/// been
/// discovered through network advertising, providing uniform access to service metadata and network
/// location details across different underlying implementations.
///
/// ## Portability
/// By abstracting the underlying service discovery mechanism, this protocol enables SwiftOCA to
/// work
/// with different network advertising implementations while providing a consistent API.
/// Platform-specific
/// implementations can conform to this protocol to provide their own service discovery
/// capabilities.
///
/// ## Usage
/// ```swift
/// let serviceInfo: any OcaNetworkAdvertisingServiceInfo = // ... discovered service
///
/// // Access basic information
/// print("Service: \(serviceInfo.name)")
/// print("Type: \(serviceInfo.serviceType)")
///
/// // Resolve to get network details
/// try await serviceInfo.resolve()
/// let hostname = try serviceInfo.hostname
/// let port = try serviceInfo.port
/// ```
///
/// ## Thread Safety
/// Conforming types must be `Sendable` and safe to use across concurrency contexts.
///
/// ## Identity
/// Services are uniquely identified by their `id` property, which combines the service name,
/// type, and domain into a stable identifier.
public protocol OcaNetworkAdvertisingServiceInfo: Sendable, Equatable, Hashable,
  Identifiable where ID == String
{
  /// The underlying network advertising service.
  var service: OcaNetworkAdvertisingService { get }

  /// The type of network advertising service (e.g., TCP, UDP).
  var serviceType: OcaNetworkAdvertisingServiceType { get }

  /// The human-readable name of the advertised service.
  var name: String { get }

  /// The network domain where the service is advertised.
  var domain: String { get }

  /// The hostname of the device providing this service.
  /// - Throws: An error if the service has not been resolved or resolution failed.
  var hostname: String { get throws }

  /// The port number on which the service is available.
  /// - Throws: An error if the service has not been resolved or resolution failed.
  var port: UInt16 { get throws }

  /// The network addresses associated with this service.
  /// - Returns: An array of `Data` objects representing network addresses.
  /// - Throws: An error if the service has not been resolved or resolution failed.
  var addresses: [Data] { get throws }

  /// The TXT records associated with this service, providing additional metadata.
  /// - Returns: A dictionary of key-value pairs from the service's TXT records.
  /// - Throws: An error if the service has not been resolved or resolution failed.
  var txtRecords: [String: String] { get throws }

  /// Resolves the service to populate network details like hostname, port, and addresses.
  ///
  /// This method must be called before accessing `hostname`, `port`, `addresses`, or `txtRecords`.
  /// Resolution is typically an asynchronous network operation that queries the advertising system.
  ///
  /// - Throws: An error if resolution fails due to network issues or service unavailability.
  func resolve() async throws
}

extension OcaNetworkAdvertisingServiceInfo {
  /// Converts the raw address data to structured socket addresses.
  ///
  /// This computed property transforms the raw `Data` addresses into typed `SocketAddress` objects
  /// that can be used for network connections. Invalid or malformed addresses are filtered out.
  ///
  /// - Returns: An array of `SocketAddress` objects derived from the service's addresses.
  /// - Throws: An error if the underlying addresses cannot be accessed (service not resolved).
  var socketAddresses: [SocketAddress] {
    get throws {
      try addresses.compactMap {
        try? AnySocketAddress(bytes: Array($0))
      }
    }
  }

  /// A unique identifier for this service constructed from its name, type, and domain.
  ///
  /// The identifier follows the format: `name.serviceType.domain` and provides a stable
  /// way to identify and compare services across discovery sessions.
  public var id: ID {
    "\(name).\(serviceType.rawValue)\(domain)"
  }
}

/// A type-erased wrapper for `OcaNetworkAdvertisingServiceInfo` conforming types.
///
/// This struct provides a way to store and work with different concrete implementations of
/// `OcaNetworkAdvertisingServiceInfo` in a uniform manner, while preserving their original
/// equality and hashing behavior. It's particularly useful when you need to store services
/// from different discovery mechanisms in the same collection.
///
/// ## Usage
/// ```swift
/// let tcpService: SomeTCPServiceInfo = // ...
/// let udpService: SomeUDPServiceInfo = // ...
///
/// let services: [AnyOcaNetworkAdvertisingServiceInfo] = [
///   AnyOcaNetworkAdvertisingServiceInfo(tcpService),
///   AnyOcaNetworkAdvertisingServiceInfo(udpService)
/// ]
/// ```
///
/// ## Type Safety
/// The wrapper preserves the original type's equality and hashing semantics by storing
/// type-specific closures, ensuring that equality comparisons work correctly even when
/// comparing services of different underlying types.
public struct AnyOcaNetworkAdvertisingServiceInfo: OcaNetworkAdvertisingServiceInfo,
  @unchecked Sendable
{
  private let _service: any OcaNetworkAdvertisingServiceInfo
  private let _equals: (any OcaNetworkAdvertisingServiceInfo) -> Bool
  private let _hash: (inout Hasher) -> ()

  public init<T: OcaNetworkAdvertisingServiceInfo>(_ service: T) {
    _service = service
    _equals = { other in
      guard let otherTyped = other as? T else { return false }
      return service == otherTyped
    }
    _hash = { hasher in
      service.hash(into: &hasher)
    }
  }

  public var service: OcaNetworkAdvertisingService {
    _service.service
  }

  public var serviceType: OcaNetworkAdvertisingServiceType {
    _service.serviceType
  }

  public var name: String {
    _service.name
  }

  public var domain: String {
    _service.domain
  }

  public var hostname: String {
    get throws {
      try _service.hostname
    }
  }

  public var port: UInt16 {
    get throws {
      try _service.port
    }
  }

  public var addresses: [Data] {
    get throws {
      try _service.addresses
    }
  }

  public var txtRecords: [String: String] {
    get throws {
      try _service.txtRecords
    }
  }

  public func resolve() async throws {
    try await _service.resolve()
  }

  public static func == (
    lhs: AnyOcaNetworkAdvertisingServiceInfo,
    rhs: AnyOcaNetworkAdvertisingServiceInfo
  ) -> Bool {
    lhs._equals(rhs._service)
  }

  public func hash(into hasher: inout Hasher) {
    _hash(&hasher)
  }
}

/// Represents the result of a network service discovery operation.
///
/// This enum encapsulates the two primary events that occur during network service browsing:
/// services being discovered and becoming available, or services disappearing from the network.
///
/// ## Usage
/// ```swift
/// for await result in browser.browseResults {
///   switch result {
///   case .added(let serviceInfo):
///     print("Discovered service: \(serviceInfo.name)")
///   case .removed(let serviceInfo):
///     print("Service disappeared: \(serviceInfo.name)")
///   }
/// }
/// ```
public enum OcaNetworkAdvertisingServiceBrowserResult: Sendable {
  /// A new service has been discovered and is now available.
  case added(any OcaNetworkAdvertisingServiceInfo)

  /// A previously discovered service is no longer available.
  case removed(any OcaNetworkAdvertisingServiceInfo)

  /// Extracts the service information from either case.
  ///
  /// This computed property provides a convenient way to access the underlying service
  /// information regardless of whether the service was added or removed.
  var info: any OcaNetworkAdvertisingServiceInfo {
    switch self {
    case let .added(info): info
    case let .removed(info): info
    }
  }
}

/// A protocol for browsing and discovering OCA network advertising services.
///
/// This protocol provides a portable abstraction for network service discovery, allowing
/// SwiftOCA to work with different underlying discovery mechanisms (such as Bonjour/mDNS
/// on Apple platforms, or other advertising protocols on different platforms) through a
/// unified interface.
///
/// ## Portability
/// Different platforms can provide their own implementations of this protocol, enabling
/// SwiftOCA to discover OCA devices regardless of the underlying network advertising
/// technology available on the platform.
///
/// ## Usage
/// ```swift
/// let browser = try SomeNetworkBrowser(serviceType: .tcp)
/// try await browser.start()
///
/// for await result in browser.browseResults {
///   switch result {
///   case .added(let service):
///     // Handle newly discovered service
///     try await service.resolve()
///     print("Found service: \(service.name) at \(try service.hostname):\(try service.port)")
///   case .removed(let service):
///     // Handle service that disappeared
///     print("Service \(service.name) is no longer available")
///   }
/// }
/// ```
///
/// ## Lifecycle
/// 1. Create a browser instance for the desired service type
/// 2. Call `start()` to begin discovery
/// 3. Process results from the `browseResults` async sequence
/// 4. Call `stop()` when discovery is no longer needed
public protocol OcaNetworkAdvertisingServiceBrowser: Sendable {
  /// Creates a new browser for discovering services of the specified type.
  ///
  /// - Parameter serviceType: The type of network advertising service to discover (TCP, UDP, etc.).
  /// - Throws: An error if the browser cannot be initialized for the specified service type.
  init(serviceType: OcaNetworkAdvertisingServiceType) throws

  /// An async sequence of service discovery results.
  ///
  /// This sequence emits `OcaNetworkAdvertisingServiceBrowserResult` values as services
  /// are discovered or removed from the network. The sequence continues until the browser
  /// is stopped or encounters an unrecoverable error.
  var browseResults: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult> { get }

  /// Starts the service discovery process.
  ///
  /// After calling this method, the browser will begin monitoring the network for services
  /// of the configured type and emit results through the `browseResults` sequence.
  ///
  /// - Throws: An error if the discovery process cannot be started.
  func start() async throws

  /// Stops the service discovery process.
  ///
  /// After calling this method, the browser will stop monitoring for new services and
  /// the `browseResults` sequence will complete.
  ///
  /// - Throws: An error if the discovery process cannot be stopped cleanly.
  func stop() throws
}
