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

import BinaryCoder
import Foundation
import SwiftOCA

extension OcaRoot {
    public func decodeCommand<U: Decodable>(_ command: Ocp1Command) throws -> U {
        // FIXME: verify parameterCount
        let decoder = Ocp1BinaryDecoder()
        do {
            return try decoder.decode(U.self, from: command.parameters.parameterData)
        } catch BinaryDecodingError.eofTooEarly {
            throw Ocp1Error.pduTooShort
        }
    }

    private func parameterCount(for mirror: Mirror) -> OcaUint8 {
        let count: OcaUint8

        switch mirror.displayStyle {
        case .struct:
            fallthrough
        case .class:
            count = OcaUint8(mirror.children.count)
        // FIXME: we'll probably need to use Echo for Optional
        default:
            count = 1
        }

        return count
    }

    private func parameterCount<T: Encodable>(for parameters: T) -> OcaUint8 {
        let parameterCount: OcaUint8

        if let parameters = parameters as? OcaParameterCountReflectable {
            parameterCount = type(of: parameters).responseParameterCount
        } else {
            let mirror = Mirror(reflecting: parameters)
            parameterCount = self.parameterCount(for: mirror)
        }

        return parameterCount
    }

    public func encodeResponse<T: Encodable>(
        _ parameters: T,
        statusCode: OcaStatus = .ok
    ) throws -> Ocp1Response {
        let encoder = Ocp1BinaryEncoder()
        let parameters = Ocp1Parameters(
            parameterCount: parameterCount(for: parameters),
            parameterData: try encoder.encode(parameters)
        )

        return Ocp1Response(statusCode: statusCode, parameters: parameters)
    }
}
