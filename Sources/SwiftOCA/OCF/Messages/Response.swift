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

public struct Ocp1Response: _Ocp1ExtendedMessageCodable, Sendable {
  public let responseSize: OcaUint32
  public let handle: OcaUint32
  public let statusCode: OcaStatus
  public let extensions: OcaList<Ocp1Extension>?
  public let parameters: Ocp1Parameters

  public var messageSize: OcaUint32 { responseSize }

  public init(
    responseSize: OcaUint32 = 0,
    handle: OcaUint32 = 0,
    statusCode: OcaStatus = .ok,
    parameters: Ocp1Parameters = Ocp1Parameters(),
    extensions: [Ocp1Extension]? = nil
  ) {
    self.responseSize = responseSize
    self.handle = handle
    self.statusCode = statusCode
    self.parameters = parameters
    self.extensions = extensions
  }

  init(bytes: borrowing[UInt8]) throws {
    try self.init(bytes: bytes, extensionsSupported: false)
  }

  init(bytes: borrowing[UInt8], extensionsSupported: Bool) throws {
    guard bytes.count >= (extensionsSupported ? 12 : 10) else {
      throw Ocp1Error.pduTooShort
    }
    responseSize = bytes.withUnsafeBytes {
      OcaUint32(bigEndian: $0.loadUnaligned(fromByteOffset: 0, as: OcaUint32.self))
    }
    handle = bytes.withUnsafeBytes {
      OcaUint32(bigEndian: $0.loadUnaligned(fromByteOffset: 4, as: OcaUint32.self))
    }
    guard let statusCode = OcaStatus(rawValue: bytes[8]) else {
      throw Ocp1Error.status(.badFormat)
    }
    self.statusCode = statusCode
    if extensionsSupported {
      let extensionsCount: OcaUint16 = bytes.withUnsafeBytes {
        OcaUint16(bigEndian: $0.loadUnaligned(fromByteOffset: 9, as: OcaUint16.self))
      }
      var offset = 11
      var extensions = [Ocp1Extension]()
      for _ in 0..<extensionsCount {
        let (`extension`, remain) = try Ocp1Decoder()._decodePartial(
          Ocp1Extension.self,
          from: bytes[offset...]
        )
        offset += remain
        extensions.append(`extension`)
      }
      self.extensions = extensions
      guard offset < bytes.count else {
        throw Ocp1Error.pduTooShort
      }
      parameters = Ocp1Parameters(
        parameterCount: bytes[offset],
        parameterData: .init(bytes[(offset + 1)...])
      )
    } else {
      parameters = Ocp1Parameters(parameterCount: bytes[9], parameterData: .init(bytes[10...]))
      extensions = nil
    }
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: responseSize.bigEndian) { bytes += $0 }
    withUnsafeBytes(of: handle.bigEndian) { bytes += $0 }
    bytes += [statusCode.rawValue]
    if let extensions {
      let extensionCount = UInt16(extensions.count)
      withUnsafeBytes(of: extensionCount.bigEndian) { bytes += $0 }
      bytes += extensions.flatMap {
        let encoded: [UInt8] = try! Ocp1Encoder().encode($0)
        return encoded
      }
    }
    bytes += [parameters.parameterCount] + parameters.parameterData
  }

  package func findExtension(with id: OcaExtensionID) -> Ocp1Extension? {
    guard let extensions else { return nil }
    return extensions.first(where: { $0.extensionID == id })
  }

  package var extendedStatusSupported: Bool {
    findExtension(with: OcaExtendedStatusExtensionID) != nil
  }

  public var bytes: [UInt8] {
    var bytes: [UInt8] = []
    encode(into: &bytes)
    return bytes
  }
}
