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

public struct Ocp1EventData: Codable, Sendable {
    let event: OcaEvent
    let eventParameters: Data

    public init(event: OcaEvent, eventParameters: Data) {
        self.event = event
        self.eventParameters = eventParameters
    }
}

public struct Ocp1NtfParams: Codable, Sendable {
    let parameterCount: OcaUint8
    let context: OcaBlob
    let eventData: Ocp1EventData

    public init(parameterCount: OcaUint8, context: OcaBlob, eventData: Ocp1EventData) {
        self.parameterCount = parameterCount
        self.context = context
        self.eventData = eventData
    }
}

public struct Ocp1Notification1: Ocp1Message, Codable, Sendable {
    let notificationSize: OcaUint32
    let targetONo: OcaONo
    let methodID: OcaMethodID
    let parameters: Ocp1NtfParams

    public var messageSize: OcaUint32 { notificationSize }

    public init(
        notificationSize: OcaUint32 = 0,
        targetONo: OcaONo,
        methodID: OcaMethodID,
        parameters: Ocp1NtfParams
    ) {
        self.notificationSize = notificationSize
        self.targetONo = targetONo
        self.methodID = methodID
        self.parameters = parameters
    }
}
