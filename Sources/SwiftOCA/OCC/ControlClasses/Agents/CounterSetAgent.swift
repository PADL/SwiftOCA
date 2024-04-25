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

open class OcaCounterSetAgent: OcaAgent {
    override open class var classID: OcaClassID { OcaClassID("1.2.19") }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1"),
        setMethodID: OcaMethodID("3.2")
    )
    public var counterSet: OcaProperty<OcaCounterSet>.PropertyValue

    public func get(counter id: OcaID16) async throws -> OcaCounter {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.3"),
            parameters: id
        )
    }

    public struct CounterNotifierParameters: Ocp1ParametersReflectable {
        public let id: OcaID16
        public let oNo: OcaONo

        public init(id: OcaID16, oNo: OcaONo) {
            self.id = id
            self.oNo = oNo
        }
    }

    public func attach(counter id: OcaID16, to oNo: OcaONo) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.4"),
            parameters: CounterNotifierParameters(id: id, oNo: oNo)
        )
    }

    public func detach(counter id: OcaID16, from oNo: OcaONo) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.5"),
            parameters: CounterNotifierParameters(id: id, oNo: oNo)
        )
    }

    public func reset() async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.6")
        )
    }

    public func reset(counter id: OcaID16) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.7"),
            parameters: id
        )
    }
}
