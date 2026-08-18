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

/// A non-finite number reaching NSJSONSerialization raises an unrecoverable
/// ObjC exception on Darwin, so a -inf dB gain bound must be re-spelled as a
/// string before it lands in a JSON object.
@Suite
struct JSONNonFiniteTests {
  @Test
  func nonFiniteValuesAreSpelledAsStrings() {
    #expect(_jsonNonFiniteSafe(Float.infinity) as? String == "Infinity")
    #expect(_jsonNonFiniteSafe(-Double.infinity) as? String == "-Infinity")
    #expect(_jsonNonFiniteSafe(Float.nan) as? String == "NaN")
  }

  @Test
  func finiteValuesPassThroughUnchanged() {
    #expect(_jsonNonFiniteSafe(Float(-10)) as? Float == -10)
    #expect(_jsonNonFiniteSafe(OcaUint16(42)) as? OcaUint16 == 42)
    #expect(_jsonNonFiniteSafe("Control Network") as? String == "Control Network")
  }

  @Test
  func reencodingProducesAValidJSONObject() throws {
    let reencoded = try JSONEncoder()
      .reencodeAsValidJSONObject(["Gain": Float(3), "MinGain": -Float.infinity])
    #expect(JSONSerialization.isValidJSONObject(["value": reencoded]))
  }

  @Test
  func typedReencodingRoundTripsNonFiniteValues() throws {
    let value: [Float] = try JSONEncoder()
      .reencodeAsValidJSONObject([-Float.infinity, 3, Float.nan])
    #expect(value[0] == -.infinity)
    #expect(value[1] == 3)
    #expect(value[2].isNaN)
  }
}
