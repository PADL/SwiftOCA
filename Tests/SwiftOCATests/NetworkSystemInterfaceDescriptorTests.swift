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

#if NonEmbeddedBuild
import Foundation
@testable import SwiftOCA
import XCTest

/// AES70-2-2023 makes OcaNetworkSystemInterfaceDescriptor a typedef of OcaBlob, so
/// OcaApplicationNetwork.SystemInterfaces is a list of blobs on the wire.
final class NetworkSystemInterfaceDescriptorTests: XCTestCase {
  /// The AES70-2-2018 structure SwiftOCA puts in the blob: a parameters blob, then an
  /// Ocp1NetworkAddress blob for 10.0.0.1:65000.
  private let content = Data([
    0x00, 0x02, 0xAA, 0xBB, // SystemInterfaceParameters
    0x00, 0x0C, // MyNetworkAddress length
    0x00, 0x08, 0x31, 0x30, 0x2E, 0x30, 0x2E, 0x30, 0x2E, 0x31, // "10.0.0.1"
    0xFD, 0xE8, // port 65000
  ])

  private var descriptor: Ocp1NetworkSystemInterfaceDescriptor {
    get throws {
      try Ocp1NetworkSystemInterfaceDescriptor(
        systemInterfaceParameters: OcaBlob(Data([0xAA, 0xBB])),
        myNetworkAddress: Ocp1NetworkAddress(address: "10.0.0.1", port: 65000).networkAddress
      )
    }
  }

  func testOcp1ListHasOneBlobPerItem() throws {
    let systemInterfaces: [OcaNetworkSystemInterfaceDescriptor] = try [descriptor.blob]
    let encoded = Data([0x00, 0x01, 0x00, 0x12]) + content // count 1, blob length 18

    XCTAssertEqual(try Ocp1Encoder().encode(systemInterfaces), encoded)
    let decoded = try Ocp1Decoder().decode(
      [OcaNetworkSystemInterfaceDescriptor].self,
      from: encoded
    )
    XCTAssertEqual(decoded, systemInterfaces)
    XCTAssertEqual(
      try decoded.first?.decode(Ocp1NetworkSystemInterfaceDescriptor.self),
      try descriptor
    )
  }

  func testOcp2ListIsAnArrayOfBase64Strings() throws {
    let systemInterfaces: [OcaNetworkSystemInterfaceDescriptor] = try [descriptor.blob]
    let encoded = try XCTUnwrap(Ocp2Encoder().encodeValue(systemInterfaces) as? [String])

    XCTAssertEqual(encoded, [content.base64EncodedString()])
    XCTAssertEqual(
      try Ocp2Decoder().decodeValue([OcaNetworkSystemInterfaceDescriptor].self, from: encoded),
      systemInterfaces
    )
  }

  func testTypedContentRoundTrips() throws {
    let parameters = Ocp1SystemInterfaceParameters(
      version: 1,
      hostname: "inferno",
      interfaceIndex: 2,
      subnetMaskLength: 24,
      defaultGateway: "10.0.0.254",
      dnsServers: "10.0.0.53",
      dnsDomainName: "local",
      linkUp: true,
      adapterSpeed: 1_000_000,
      parametersType: .dhcp,
      macAddress: (0x00, 0x0B, 0x5E, 0x01, 0x02, 0x03),
      linkType: .ethernetWired
    )
    let address = Ocp1NetworkAddress(address: "fe80::1", port: 65000)
    let blob: OcaNetworkSystemInterfaceDescriptor = try Ocp1NetworkSystemInterfaceDescriptor(
      systemInterfaceParameters: parameters,
      myNetworkAddress: address
    ).blob

    let decoded = try blob.decode(Ocp1NetworkSystemInterfaceDescriptor.self)
    XCTAssertEqual(try decoded.networkAddress, address)
    XCTAssertEqual(try decoded.parameters.hostname, "inferno")
    XCTAssertEqual(try decoded.parameters.subnetMaskLength, 24)
    XCTAssertTrue(decoded.description.contains("fe80::1"))
  }
}
#endif
