//
// Copyright (c) 2023 PADL Software Pty Ltd
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

public func Ocp1BinaryEncoder() -> BinaryEncoder {
    BinaryEncoder(config: .ocp1Configuration)
}

public func Ocp1BinaryDecoder() -> BinaryDecoder {
    BinaryDecoder(config: .ocp1Configuration)
}

extension BinaryCodingConfiguration {
    static var ocp1Configuration: Self {
        BinaryCodingConfiguration(
            endianness: .bigEndian,
            stringEncoding: .utf8,
            stringTypeStrategy: .lengthTagged,
            variableSizedTypeStrategy: .lengthTaggedArrays
        )
    }
}

// private API for SwiftOCADevice

public extension Encoder {
    var _isOcp1BinaryEncoder: Bool {
        self is BinaryEncoderImpl
    }
}

public extension Decoder {
    var _isOcp1BinaryDecoder: Bool {
        self is BinaryDecoderImpl
    }
}
