//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

import BinaryParsing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct Ocp1Response: _Ocp1MessageCodable, Sendable {
  public let responseSize: OcaUint32
  public let handle: OcaUint32
  public let statusCode: OcaStatus
  public let parameters: OcaParameters

  public var messageSize: OcaUint32 { responseSize }

  public init(
    responseSize: OcaUint32 = 0,
    handle: OcaUint32 = 0,
    statusCode: OcaStatus = .ok,
    parameters: OcaParameters = OcaParameters()
  ) {
    self.responseSize = responseSize
    self.handle = handle
    self.statusCode = statusCode
    self.parameters = parameters
  }

  init(parsing input: inout ParserSpan) throws {
    responseSize = try OcaUint32(parsingBigEndian: &input)
    handle = try OcaUint32(parsingBigEndian: &input)
    statusCode = try OcaStatus(parsing: &input)
    parameters = try OcaParameters(
      parameterCount: OcaUint8(parsing: &input),
      parameterData: Data(parsingRemainingBytes: &input)
    )
  }

  @_spi(SwiftOCAPrivate)
  public var encodedSize: Int {
    2 * MemoryLayout<OcaUint32>.size + 1 + 1 + parameters.parameterData.count
  }

  /// `responseSize` is written as the encoded size, whatever its stored value.
  @_spi(SwiftOCAPrivate)
  public func encode(into output: inout OutputRawSpan) {
    output.append(bigEndian: OcaUint32(encodedSize))
    output.append(bigEndian: handle)
    output.append(statusCode.rawValue)
    output.append(parameters.parameterCount)
    output.append(contentsOf: parameters.parameterData)
  }
}
