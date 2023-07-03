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

public enum OcaNotificationDeliveryMode: OcaUint8, Codable {
    case reliable = 1
    case fast = 2
}

public struct OcaEventID: Codable, Hashable, CustomStringConvertible {
    let defLevel: OcaUint16
    let eventIndex: OcaUint16

    init(_ string: OcaString) {
        let s = string.split(separator: ".", maxSplits: 1).map { OcaUint16($0)! }
        defLevel = s[0]
        eventIndex = s[1]
    }

    init(defLevel: OcaUint16, eventIndex: OcaUint16) {
        self.defLevel = defLevel
        self.eventIndex = eventIndex
    }

    public var description: String {
        "\(defLevel).\(eventIndex)"
    }
}

public struct OcaEvent: Codable, Hashable, Equatable {
    let emitterONo: OcaONo
    let eventID: OcaEventID
}

public enum OcaPropertyChangeType: OcaUint8, Codable, Equatable {
    case currentChanged = 1
    case minChanged = 2
    case maxChanged = 3
    case itemAdded = 4
    case itemChanged = 5
    case itemDeleted = 6
}

public struct OcaPropertyChangedEventData<T: Codable>: Codable {
    let propertyID: OcaPropertyID
    let propertyValue: T
    let changeType: OcaPropertyChangeType
}

let OcaPropertyChangedEventID = OcaEventID(defLevel: 1, eventIndex: 1)
