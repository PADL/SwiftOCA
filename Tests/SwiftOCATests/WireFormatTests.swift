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
@testable import SwiftOCA
import Testing

/// Types whose coding AES70 fixes, as AES70-2 and AES70.js both have it.
@Suite struct WireFormatTests {
  @Test func aTimeIntervalIsAFloat32() throws {
    let encoded: Data = try Ocp1Encoder().encode(OcaTimeInterval(1.5))
    #expect(encoded == Data([0x3F, 0xC0, 0x00, 0x00]))
  }

  @Test func aRelativeLevelIsItsValueThenItsReference() throws {
    let level = OcaDBr(value: -6, ref: 20)
    let encoded: Data = try Ocp1Encoder().encode(level)
    #expect(encoded == Data([0xC0, 0xC0, 0x00, 0x00, 0x41, 0xA0, 0x00, 0x00]))
    #expect(try Ocp1Decoder().decode(OcaDBr.self, from: encoded) == level)
    // ordered by the level each stands for
    #expect(OcaDBr(value: -6, ref: 20) > OcaDBr(value: 10, ref: 0))
  }

  @Test func theTimeEnumerationsHaveAES70_2023sValues() {
    #expect(OcaTimeDeliveryMechanism.aes11.rawValue == 11)
    #expect(OcaTimeDeliveryMechanism.gps.rawValue == 13)
    #expect(OcaTimeDeliveryMechanism.inrss.rawValue == 17)
    #expect(OcaTimeReferenceType.tai.rawValue == 3)
    #expect(OcaTimeProtocol.aes11.rawValue == 9)
    #expect(OcaTimeProtocol.genlock.rawValue == 10)
    #expect(OcaResetCause.unknown.rawValue == 255)
  }
}
