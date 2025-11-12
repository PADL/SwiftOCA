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

#if canImport(Darwin)

import AsyncAlgorithms
import Foundation

extension NetService: @unchecked Sendable {}

public final class OcaBrowser: NSObject, NetServiceBrowserDelegate {
  public enum Result: Sendable {
    case didNotSearch(Error)
    case didFind(NetService)
    case didRemove(NetService)

    var result: Swift.Result<NetService, Error> {
      switch self {
      case let .didFind(service): .success(service)
      case let .didRemove(service): .success(service)
      case let .didNotSearch(error): .failure(error)
      }
    }
  }

  private let browser: NetServiceBrowser
  public let channel: AsyncChannel<Result>

  public init(serviceType: OcaNetworkAdvertisingServiceType) {
    browser = NetServiceBrowser()
    channel = AsyncChannel<Result>()
    super.init()
    browser.delegate = self
    browser.schedule(in: .main, forMode: .default)
    browser.searchForServices(ofType: serviceType.rawValue, inDomain: "local.")
  }

  deinit {
    browser.stop()
    browser.remove(from: .main, forMode: .default)
  }

  public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {}

  private func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch error: Error) {
    Task { await channel.send(Result.didNotSearch(error)) }
  }

  public func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    Task { await channel.send(Result.didFind(service)) }
  }

  public func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didRemove service: NetService,
    moreComing: Bool
  ) {
    Task { await channel.send(Result.didRemove(service)) }
  }

  public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
    channel.finish()
  }
}

final class OcaResolverDelegate: NSObject, NetServiceDelegate, Sendable {
  let channel: AsyncThrowingChannel<Data, Error>

  init(_ channel: AsyncThrowingChannel<Data, Error>) {
    self.channel = channel
  }

  deinit {
    channel.finish()
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    guard let addresses = sender.addresses, !addresses.isEmpty else {
      channel.fail(Ocp1Error.serviceResolutionFailed)
      return
    }

    Task {
      for address in addresses {
        await channel.send(address)
      }
    }
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    let errorCode = errorDict[NetService.errorCode]!.intValue
    let errorDomain = errorDict[NetService.errorDomain]!.stringValue

    channel.fail(NSError(domain: errorDomain, code: errorCode))
  }
}

fileprivate protocol Ocp1ConnectionFactory {}

extension Ocp1ConnectionFactory {
  init(reassigningSelfTo other: Self) async {
    self = other
  }
}

extension Ocp1Connection: Ocp1ConnectionFactory {
  public convenience init(
    _ netService: NetService,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) async throws {
    guard let serviceType = OcaNetworkAdvertisingServiceType(rawValue: netService.type) else {
      throw Ocp1Error.unknownServiceType
    }

    let channel = AsyncThrowingChannel<Data, Error>()
    let delegate = OcaResolverDelegate(channel)
    netService.delegate = delegate
    netService.schedule(in: RunLoop.main, forMode: .default)
    defer { netService.remove(from: RunLoop.main, forMode: .default) }
    netService.resolve(withTimeout: 5)

    for try await address in channel {
      // FIXME: support IPv6
      guard address.withUnsafeBytes({ unbound -> Bool in
        unbound.withMemoryRebound(to: sockaddr.self) { cSockAddr -> Bool in
          cSockAddr.baseAddress!.pointee.sa_family == AF_INET
        }
      }) == true else {
        continue
      }
      channel.finish()

      switch serviceType {
      case .tcp:
        try await self
          .init(
            reassigningSelfTo: Ocp1TCPConnection(
              deviceAddress: address,
              options: options
            ) as! Self
          )
        return
      case .udp:
        try await self
          .init(
            reassigningSelfTo: Ocp1UDPConnection(
              deviceAddress: address,
              options: options
            ) as! Self
          )
        return
      default:
        throw Ocp1Error.unknownServiceType
      }
    }

    throw Ocp1Error.serviceResolutionFailed
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
