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

import Foundation

public struct Ocp1Parameters: Codable, Sendable {
    public var parameterCount: OcaUint8
    public var parameterData: Data

    public init(parameterCount: OcaUint8, parameterData: Data) {
        self.parameterCount = parameterCount
        self.parameterData = parameterData
    }

    public init() {
        self.init(parameterCount: 0, parameterData: Data())
    }
}

public struct Ocp1Command: Ocp1Message, Codable, Sendable {
    public let commandSize: OcaUint32
    public let handle: OcaUint32
    public let targetONo: OcaONo
    public let methodID: OcaMethodID
    public let parameters: Ocp1Parameters

    public var messageSize: OcaUint32 { commandSize }

    public init(
        commandSize: OcaUint32,
        handle: OcaUint32,
        targetONo: OcaONo,
        methodID: OcaMethodID,
        parameters: Ocp1Parameters
    ) {
        self.commandSize = commandSize
        self.handle = handle
        self.targetONo = targetONo
        self.methodID = methodID
        self.parameters = parameters
    }
}
