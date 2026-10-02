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

#if canImport(Darwin) || canImport(dnssd)

import Foundation
import Logging
@testable import SwiftOCA
import Synchronization
import Testing

private struct MockServiceInfo: OcaNetworkAdvertisingServiceInfo {
  let name: String

  var service: OcaNetworkAdvertisingService { .mDNS_DNSSD }
  var serviceType: OcaNetworkAdvertisingServiceType { .tcp }
  var domain: String { "local." }
  var hostname: String { "mock.local." }
  var port: UInt16 { 65000 }
  var addresses: [Data] { [] }
  var txtRecords: [String: String] { [:] }

  func resolve() async throws {}
}

private extension OcaNetworkAdvertisingServiceBrowserResult {
  var text: String {
    switch self {
    case let .added(info): "added \(info.name)"
    case let .removed(info): "removed \(info.name)"
    }
  }
}

private final class RecordedMessages: Sendable {
  private let messages = Mutex([String]())

  var all: [String] { messages.withLock { $0 } }

  func append(_ message: String) { messages.withLock { $0.append(message) } }
}

private struct RecordingLogHandler: LogHandler {
  let recorded: RecordedMessages
  var metadata = Logger.Metadata()
  var logLevel = Logger.Level.trace

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    recorded.append("\(level) \(message)")
  }
}

@Suite
struct ConnectionBrokerBrowsingTests {
  private typealias Result = OcaNetworkAdvertisingServiceBrowserResult

  /// Feeds `results` through the broker's dispatch and returns what `body` handled, in
  /// the order it finished handling it.
  private func handled(
    _ results: [Result],
    _ body: @escaping @Sendable (Result) async -> ()
  ) async -> [String] {
    let (stream, continuation) = AsyncStream<Result>.makeStream()
    for result in results { continuation.yield(result) }
    continuation.finish()

    let (finished, finishedContinuation) = AsyncStream<String>.makeStream()
    await OcaConnectionBroker._forEachBrowseResult(in: stream) { result in
      await body(result)
      finishedContinuation.yield(result.text)
    }

    var order = [String]()
    for await text in finished {
      order.append(text)
      if order.count == results.count { break }
    }
    return order
  }

  /// The first service does not resolve until the second has been handled, which would
  /// never happen were they handled one after the other.
  @Test(.timeLimit(.minutes(1)))
  func aSlowServiceDoesNotHoldUpTheOthers() async {
    let (gate, gateContinuation) = AsyncStream<()>.makeStream()

    let order = await handled([
      .added(MockServiceInfo(name: "Slow")),
      .added(MockServiceInfo(name: "Quick")),
    ]) { result in
      if result.info.name == "Slow" {
        for await _ in gate { break }
      } else {
        gateContinuation.yield()
      }
    }

    #expect(order == ["added Quick", "added Slow"])
  }

  @Test(.timeLimit(.minutes(1)))
  func theResultsForOneServiceKeepTheirOrder() async {
    let service = MockServiceInfo(name: "Device")

    let order = await handled([.added(service), .removed(service), .added(service)]) { result in
      // the first to arrive takes the longest
      if case .added = result { try? await Task.sleep(for: .milliseconds(20)) }
    }

    #expect(order == ["added Device", "removed Device", "added Device"])
  }

  #if !canImport(Darwin)
  /// With no service type to browse for, as with no responder to ask, a dns_sd browser
  /// cannot start. This trapped; now it is logged, and tried again on a refresh.
  @Test
  func aBrowserThatCannotStartIsLoggedAndTriedAgain() async {
    let recorded = RecordedMessages()
    let logger = Logger(label: "test") { _ in RecordingLogHandler(recorded: recorded) }
    let failure = "warning cannot browse for : serviceBrowsingUnavailable"

    let broker = await OcaConnectionBroker(serviceTypes: [.none], logger: logger)
    #expect(recorded.all == [failure])

    await broker.refreshBrowsing()
    #expect(recorded.all == [failure, failure])
  }
  #endif
}

#endif
