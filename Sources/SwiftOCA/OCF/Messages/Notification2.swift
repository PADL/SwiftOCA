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

public enum Ocp1Notification2Type: OcaUint8, Codable, Sendable {
    case event = 0
    case exception = 1
}

public enum Ocp1Notification2ExceptionType: OcaUint8, Equatable, Codable, Sendable {
    case unspecified = 0
    case cancelledByDevice = 1
    case objectDeleted = 2
    case deviceError = 3
}

public struct Ocp1Notification2ExceptionData: Equatable, Codable, Sendable, Error {
    let exceptionType: Ocp1Notification2ExceptionType
    let tryAgain: OcaBoolean
    let exceptionData: OcaBlob

    public init(
        exceptionType: Ocp1Notification2ExceptionType,
        tryAgain: OcaBoolean,
        exceptionData: OcaBlob
    ) {
        self.exceptionType = exceptionType
        self.tryAgain = tryAgain
        self.exceptionData = exceptionData
    }
}

public struct Ocp1Notification2: Ocp1Message, Codable, Sendable {
    let notificationSize: OcaUint32
    let event: OcaEvent
    let notificationType: Ocp1Notification2Type
    let data: Data

    public var messageSize: OcaUint32 { notificationSize }

    public init(
        notificationSize: OcaUint32,
        event: OcaEvent,
        notificationType: Ocp1Notification2Type,
        data: Data
    ) {
        self.notificationSize = notificationSize
        self.event = event
        self.notificationType = notificationType
        self.data = data
    }

    func throwIfException() throws {
        guard notificationType == .exception else { return }
        let decoder = Ocp1BinaryDecoder()
        let exception = try decoder.decode(
            Ocp1Notification2ExceptionData.self,
            from: data
        )
        throw Ocp1Error.exception(exception)
    }
}
