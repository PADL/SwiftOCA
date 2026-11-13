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

@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

final class Aes67StreamEndpointRegistryTests: XCTestCase {
  private static let registryONo: OcaONo = 0x0001_0030

  private static func entry(
    _ name: String,
    port: OcaUint16,
    sdpString: OcaSDPString = "",
    mediaID: OcaString? = nil
  ) -> Aes67StreamEndpointDescriptor {
    Aes67StreamEndpointDescriptor(
      idExternal: OcaBlob(Array(name.utf8)),
      addresses: [Aes67StreamTransportAddress(ipAddress: .ip4("239.1.2.3"), port: port)],
      direction: .output,
      streamMode: OcaMediaStreamMode(
        frameFormat: .rtp,
        encodingType: "audio/L24",
        samplingRate: 48000,
        channelCount: 8,
        packetTime: 1e-3
      ),
      streamCastMode: .multicast,
      sdpString: sdpString,
      mediaIDType: mediaID == nil ? .none : .mid,
      mediaID: mediaID ?? "",
      timestamp: OcaTime(seconds: 1, nanoseconds: 0)
    )
  }

  /// Two streams in one description, told apart by a=mid.
  private static let twoStreamSDP: OcaSDPString = [
    "v=0", "o=- 1 1 IN IP4 10.0.0.1", "s=pair", "t=0 0",
    "m=audio 5010 RTP/AVP 96", "c=IN IP4 239.1.2.3/32", "a=rtpmap:96 L24/48000/8", "a=mid:main",
    "m=audio 5012 RTP/AVP 96", "c=IN IP4 239.1.2.4/32", "a=rtpmap:96 L24/48000/2", "a=mid:aux",
  ].joined(separator: "\r\n") + "\r\n"

  @OcaDevice
  func testRegistryEntriesAreKeyedByExternalID() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let registry = try await SwiftOCADevice.Aes67StreamEndpointRegistry(
      objectNumber: Self.registryONo,
      role: "Stream Source Registry",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    registry.registry = [Self.entry("stage left", port: 5004)]
    let client: SwiftOCA.Aes67StreamEndpointRegistry = try await harness.resolve(Self.registryONo)

    let entries = try await client.$registry._getValue(client, flags: [])
    XCTAssertEqual(entries, registry.registry)
    let stageLeft = try await client.getRegistryEntry(idExternal: OcaBlob(Array("stage left".utf8)))
    XCTAssertEqual(stageLeft.addresses.first?.port, 5004)

    try await client.addRegistryEntry(entry: Self.entry("stage right", port: 5006))
    XCTAssertEqual(registry.registry.count, 2)
    await XCTAssertThrowsStatus(.invalidRequest) {
      try await client.addRegistryEntry(entry: Self.entry("stage right", port: 5008))
    }

    let multistream = Self.entry(
      "stage right",
      port: 5010,
      sdpString: Self.twoStreamSDP,
      mediaID: "main"
    )
    try await client.setRegistryEntry(entry: multistream)
    let stageRight = try await client
      .getRegistryEntry(idExternal: OcaBlob(Array("stage right".utf8)))
    XCTAssertEqual(stageRight, multistream)
    XCTAssertEqual(stageRight.mediaIDType, .mid)
    XCTAssertEqual(stageRight.mediaID, "main")
    XCTAssertEqual(
      try MediaStreamSDP.selectStream(
        in: stageRight.sdpString,
        mediaIDType: stageRight.mediaIDType,
        mediaID: stageRight.mediaID
      ),
      MediaStreamSDP.streams(in: Self.twoStreamSDP)[0]
    )

    try await client.deleteRegistryEntry(idExternal: OcaBlob(Array("stage left".utf8)))
    XCTAssertEqual(registry.registry.map(\.idExternal), [OcaBlob(Array("stage right".utf8))])
    await XCTAssertThrowsStatus(.parameterOutOfRange) {
      try await client.getRegistryEntry(idExternal: OcaBlob(Array("stage left".utf8)))
    }
    await XCTAssertThrowsStatus(.parameterOutOfRange) {
      try await client.setRegistryEntry(entry: Self.entry("stage left", port: 5004))
    }
    await XCTAssertThrowsStatus(.notImplemented) {
      try await client.addRegistryEntriesFromSDP(sdpString: "v=0\r\n")
    }
  }
}
