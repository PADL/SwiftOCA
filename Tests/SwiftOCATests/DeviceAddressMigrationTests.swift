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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif
@testable import SocketAddress
@testable import SwiftOCA
import Testing

/// A device advertised by a multi-homed host is offered on every interface, so
/// its candidate address set gains and loses secondary entries while the
/// address in use stays reachable. Migrating the live connection on those
/// changes drops a working connection, and `.automaticReconnect` then repeats
/// it on the next advertisement.
@Suite
struct DeviceAddressMigrationTests {
  static func address(_ presentation: String) throws -> AnySocketAddress {
    try AnySocketAddress(family: sockaddr_in.family, presentationAddress: presentation)
  }

  @Test
  func migratesWhenTheConnectedAddressIsWithdrawn() throws {
    let a = try Self.address("10.10.32.3")
    let b = try Self.address("10.10.33.252")
    let state = Ocp1DeviceAddressState(addresses: [a], connectedAddress: a)

    #expect(state.requiresMigration(replacingWith: [b]))
  }

  @Test
  func doesNotMigrateWhenASecondaryAddressIsAdded() throws {
    let a = try Self.address("10.10.32.3")
    let b = try Self.address("10.10.33.252")
    let state = Ocp1DeviceAddressState(addresses: [a], connectedAddress: a)

    #expect(!state.requiresMigration(replacingWith: [a, b]))
  }

  @Test
  func doesNotMigrateWhenASecondaryAddressIsWithdrawn() throws {
    let a = try Self.address("10.10.32.3")
    let b = try Self.address("10.10.33.252")
    let state = Ocp1DeviceAddressState(addresses: [a, b], connectedAddress: a)

    #expect(!state.requiresMigration(replacingWith: [a]))
  }

  @Test
  func doesNotMigrateWhenOnlyThePreferenceOrderChanges() throws {
    let a = try Self.address("10.10.32.3")
    let b = try Self.address("10.10.33.252")
    // connected to the non-preferred candidate, as happens when the preferred
    // one was unreachable at connect time
    let state = Ocp1DeviceAddressState(addresses: [a, b], connectedAddress: b)

    #expect(!state.requiresMigration(replacingWith: [b, a]))
  }

  @Test
  func migratesWhileDisconnected() throws {
    // nothing to preserve: the decision is left to deviceAddressesDidChange(),
    // which no-ops unless a connection is live
    let a = try Self.address("10.10.32.3")
    let state = Ocp1DeviceAddressState(addresses: [a], connectedAddress: nil)

    #expect(state.requiresMigration(replacingWith: [try Self.address("10.10.33.252")]))
  }
}
