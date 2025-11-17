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

#if canImport(Darwin)

import AsyncAlgorithms
import AsyncExtensions
import Foundation

extension NetService: @unchecked Sendable {}

private final class _NetServiceInfo: OcaNetworkAdvertisingServiceInfo {
  private let _netService: NetService

  init(netService: NetService) { _netService = netService }

  var service: OcaNetworkAdvertisingService { .mDNS_DNSSD }

  var serviceType: OcaNetworkAdvertisingServiceType {
    OcaNetworkAdvertisingServiceType(rawValue: _netService.type)!
  }

  var name: String { _netService.name }
  var domain: String { _netService.domain }

  var hostname: String {
    get throws {
      guard let hostname = _netService.hostName else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return hostname
    }
  }

  var addresses: [Data] {
    get throws {
      guard let addresses = _netService.addresses else {
        throw Ocp1Error.serviceResolutionFailed
      }
      return addresses
    }
  }

  var port: UInt16 {
    get throws {
      UInt16(_netService.port)
    }
  }

  var txtRecords: [String: String] {
    get throws {
      guard let txtRecordData = _netService.txtRecordData()
      else { throw Ocp1Error.serviceResolutionFailed }
      return NetService.dictionary(fromTXTRecord: txtRecordData)
    }
  }

  func resolve() async throws {
    final class _ResolverHelper: NSObject, NetServiceDelegate {
      let continuation: CheckedContinuation<(), Error>

      init(_ continuation: CheckedContinuation<(), Error>) { self.continuation = continuation }

      func netServiceDidResolveAddress(_ sender: NetService) {
        continuation.resume(returning: ())
      }

      func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let errorCode = errorDict[NetService.errorCode]!.intValue
        let errorDomain = errorDict[NetService.errorDomain]!.stringValue

        continuation.resume(throwing: NSError(domain: errorDomain, code: errorCode))
      }
    }

    var resolverHelper: _ResolverHelper?

    try await withCheckedThrowingContinuation { continuation in
      resolverHelper = _ResolverHelper(continuation)
      _netService.delegate = resolverHelper
      _netService.schedule(in: RunLoop.main, forMode: .default)
      _netService.resolve(withTimeout: 1)
    }

    _netService.remove(from: RunLoop.main, forMode: .default)
    _netService.delegate = nil
  }

  static func == (lhs: _NetServiceInfo, rhs: _NetServiceInfo) -> Bool {
    lhs.service == rhs.service && lhs.serviceType == rhs.serviceType && lhs._netService
      .isEqual(rhs._netService)
  }

  func hash(into hasher: inout Hasher) {
    service.hash(into: &hasher)
    serviceType.hash(into: &hasher)
    _netService.hash(into: &hasher)
  }
}

public final class OcaNetServiceBrowser: NSObject, OcaNetworkAdvertisingServiceBrowser,
  NetServiceBrowserDelegate
{
  private let _browser = NetServiceBrowser()
  private let _serviceType: OcaNetworkAdvertisingServiceType
  private let _browseResultsContinuation: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>
    .Continuation
  public let browseResults: AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>

  public init(serviceType: OcaNetworkAdvertisingServiceType) throws {
    _serviceType = serviceType
    let (stream, continuation) = AsyncStream<OcaNetworkAdvertisingServiceBrowserResult>.makeStream()
    browseResults = stream
    _browseResultsContinuation = continuation
    super.init()
    _browser.delegate = self
  }

  public func start() async throws {
    _browser.searchForServices(ofType: _serviceType.rawValue, inDomain: "local.")
    _browser.schedule(in: .main, forMode: .default)
  }

  private func _stop() {
    _browser.stop()
    _browser.remove(from: .main, forMode: .default)
  }

  public func stop() throws {
    _stop()
  }

  deinit {
    _stop()
  }

  public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {}

  private func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch error: Error) {}

  public func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    _browseResultsContinuation.yield(.added(_NetServiceInfo(netService: service)))
  }

  public func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didRemove service: NetService,
    moreComing: Bool
  ) {
    _browseResultsContinuation.yield(.removed(_NetServiceInfo(netService: service)))
  }

  public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
    _browseResultsContinuation.finish()
  }
}

extension NetService {
  /// Decode the TXT record as a string dictionary, or [:] if the data is malformed
  static func dictionary(fromTXTRecord txtData: Data) -> [String: String] {
    // https://stackoverflow.com/questions/40193911/nsnetservice-dictionaryfromtxtrecord-fails-an-assertion-on-invalid-input
    var result = [String: String]()
    var data = txtData

    while !data.isEmpty {
      // The first byte of each record is its length, so prefix that much data
      let recordLength = Int(data.removeFirst())
      guard data.count >= recordLength else { return [:] }
      let recordData = data[..<(data.startIndex + recordLength)]
      data = data.dropFirst(recordLength)

      guard let record = String(bytes: recordData, encoding: .utf8) else { return [:] }
      // The format of the entry is "key=value"
      // (According to the reference implementation, = is optional if there is no value,
      // and any equals signs after the first are part of the value.)
      // `ommittingEmptySubsequences` is necessary otherwise an empty string will crash the next
      // line
      let keyValue = record.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let key = String(keyValue[0])
      // If there's no value, make the value the empty string
      switch keyValue.count {
      case 1:
        result[key] = ""
      case 2:
        result[key] = String(keyValue[1])
      default:
        fatalError()
      }
    }

    return result
  }
}

#endif
