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

#if canImport(dnssd)

@_spi(SwiftOCAPrivate) import SwiftOCA
@_spi(SwiftOCAPrivate) import SwiftOCADevice
import XCTest

/// Exercises registration, browsing and resolution against whichever DNS-SD responder
/// the host runs, and is skipped where it runs none.
final class DNSServiceRegistrationTests: XCTestCase {
  private static let regType = "_swiftoca-test._tcp"

  /// The first value of `stream`, or nil if none arrives in time.
  private func first<T: Sendable>(
    of stream: AsyncStream<T>,
    within timeout: Duration = .seconds(5),
    where predicate: @escaping @Sendable (T) -> Bool = { _ in true }
  ) async -> T? {
    await withTaskGroup(of: T?.self) { group in
      group.addTask {
        for await value in stream where predicate(value) { return value }
        return nil
      }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let value = await group.next() ?? nil
      group.cancelAll()
      return value
    }
  }

  private func resolve(_ found: DNSServiceBrowseResult) async -> DNSServiceResolution? {
    await first(of: DNSServiceDiscovery.resolve(
      name: found.name,
      regType: found.regType,
      domain: found.domain
    ))
  }

  func testARegisteredServiceIsFoundAndItsTXTRecordCanBeReplaced() async throws {
    let name = "SwiftOCA test \(UInt32.random(in: 0...UInt32.max))"
    let registration: DNSServiceRegistration
    do {
      registration = try await DNSServiceRegistration(
        name: name,
        regType: Self.regType,
        port: 49152,
        txtRecord: [("txtvers", "1"), ("ver_slf", "0")]
      )
    } catch {
      throw XCTSkip("no DNS-SD responder to register with: \(error)")
    }

    let browse = try DNSServiceDiscovery.browse(regType: Self.regType)
    guard let found = await first(of: browse, where: { $0.isAdded && $0.name == name }) else {
      await registration.deregister()
      throw XCTSkip("the DNS-SD responder did not report the registered service")
    }

    let resolved = await resolve(found)
    XCTAssertEqual(resolved?.port, 49152)
    XCTAssertEqual(resolved?.txtRecords, ["txtvers": "1", "ver_slf": "0"])

    try await registration.update(txtRecord: [("txtvers", "1"), ("ver_slf", "1")])
    // the responder answers from its cache until the new record has been announced
    var updated: DNSServiceResolution?
    for _ in 0..<20 {
      updated = await resolve(found)
      if updated?.txtRecords["ver_slf"] == "1" { break }
      try await Task.sleep(for: .milliseconds(250))
    }
    XCTAssertEqual(updated?.txtRecords, ["txtvers": "1", "ver_slf": "1"])

    await registration.deregister()
    let removed = await first(of: browse, where: { !$0.isAdded && $0.name == name })
    XCTAssertNotNil(removed)

    do {
      try await registration.update(txtRecord: [])
      XCTFail("a deregistered service has no TXT record to replace")
    } catch {
      XCTAssertEqual(error as? DNSServiceError, .badReference)
    }
  }
}

#endif
