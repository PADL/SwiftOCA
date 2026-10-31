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

import Foundation
@_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import XCTest

/// A controller outside Swift has only PDUs: it can't be an `OcaLocalConnection`.
final class LocalDeviceEndpointTests: XCTestCase {
  func testRawPDUsReachTheDeviceAndItsResponsesReturn() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: .ocp1)
    let task = Task { try? await endpoint.run() }
    defer { task.cancel() }

    let command = Ocp1Command(
      handle: 1,
      targetONo: OcaRootBlockONo,
      methodID: OcaMethodID("1.1"),
      parameters: OcaParameters()
    )
    await endpoint.deliver(
      request: try OcaConnection.encodeOcp1MessagePdu([command], type: .ocaCmdRrq)
    )

    var iterator = endpoint.responses.makeAsyncIterator()
    let next = await iterator.next()
    let response = try XCTUnwrap(next)
    XCTAssertEqual(response.first, Ocp1SyncValue)
    XCTAssertEqual(response[response.startIndex + 7], OcaMessageType.ocaRsp.rawValue)
  }
}
