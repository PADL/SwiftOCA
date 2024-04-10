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

public struct OcaCounter: Codable, Sendable {
    public let id: OcaID16
    public let value: OcaUint64
    public let innitialValue: OcaUint64
    public let role: OcaString
    public let notifiers: OcaList<OcaONo>

    public init(
        id: OcaID16,
        value: OcaUint64,
        innitialValue: OcaUint64,
        role: OcaString,
        notifiers: OcaList<OcaONo>
    ) {
        self.id = id
        self.value = value
        self.innitialValue = innitialValue
        self.role = role
        self.notifiers = notifiers
    }
}

public typealias OcaCounterSetID = OcaBlob

public struct OcaCounterSet: Codable, Sendable {
    public let id: OcaCounterSetID
    public let counter: OcaList<OcaCounter>

    public init(id: OcaCounterSetID, counter: OcaList<OcaCounter>) {
        self.id = id
        self.counter = counter
    }
}

public struct OcaCounterUpdate: Codable, Sendable {
    public let counterSetID: OcaCounterSetID
    public let counterID: OcaID16
    public let value: OcaUint64

    public init(counterSetID: OcaCounterSetID, counterID: OcaID16, value: OcaUint64) {
        self.counterSetID = counterSetID
        self.counterID = counterID
        self.value = value
    }
}
