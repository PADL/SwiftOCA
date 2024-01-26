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

// private API for SwiftOCADevice

public extension Encoder {
    var _isOcp1Encoder: Bool {
        self is Ocp1EncoderImpl
    }
}

public extension Decoder {
    var _isOcp1Decoder: Bool {
        self is Ocp1DecoderImpl
    }
}

public protocol Ocp1LongList {}
public protocol Ocp1ParametersReflectable: Codable {}

public func _ocp1ParameterCount<T>(type: T.Type) -> OcaUint8 {
    if type is Ocp1ParametersReflectable.Type {
        var count: OcaUint8 = 0
        _forEachField(of: type) { _, _, _, _ in
            count += 1
            return true
        }
        return count
    } else {
        return 1
    }
}

public func _ocp1ParameterCount<T>(value: T) -> OcaUint8 {
    _ocp1ParameterCount(type: type(of: value))
}
