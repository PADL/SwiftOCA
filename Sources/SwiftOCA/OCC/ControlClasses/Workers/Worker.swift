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

open class OcaWorker: OcaRoot {
    override public class var classID: OcaClassID { OcaClassID("1.1.1") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("2.1"),
        getMethodID: OcaMethodID("2.1"),
        setMethodID: OcaMethodID("2.2")
    )
    public var enabled: OcaProperty<OcaBoolean>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.2"),
        getMethodID: OcaMethodID("2.5")
    )
    public var ports: OcaProperty<OcaList<OcaPort>>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.3"),
        getMethodID: OcaMethodID("2.8"),
        setMethodID: OcaMethodID("2.9")
    )
    public var label: OcaProperty<OcaString>.PropertyValue

    // 2.4
    @OcaProperty(
        propertyID: OcaPropertyID("2.4"),
        getMethodID: OcaMethodID("2.10")
    )
    public var owner: OcaProperty<OcaONo>.PropertyValue

    // TODO: this is optional, need to check if this works
    @OcaProperty(
        propertyID: OcaPropertyID("2.5"),
        getMethodID: OcaMethodID("2.11"),
        setMethodID: OcaMethodID("2.12")
    )
    public var latency: OcaProperty<OcaTimeInterval?>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.6"),
        getMethodID: OcaMethodID("2.14"),
        setMethodID: OcaMethodID("2.15")
    )
    public var portClockMap: OcaProperty<OcaMap<OcaPortID, OcaPortClockMapEntry>>.PropertyValue

    // 2.3
    public func add(
        port label: OcaString,
        mode: OcaPortMode
    ) async throws -> OcaPortID {
        struct AddPortParameters: Ocp1ParametersReflectable {
            let label: OcaString
            let mode: OcaPortMode
        }
        let params = AddPortParameters(label: label, mode: mode)
        return try await sendCommandRrq(
            methodID: OcaMethodID("2.3"),
            parameters: params
        )
    }

    // 2.4
    public func delete(port id: OcaPortID) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("2.4"),
            parameters: id
        )
    }

    // 2.6
    public func get(portID: OcaPortID) async throws -> OcaString {
        let params = OcaGetPortNameParameters(portID: portID)
        return try await sendCommandRrq(
            methodID: OcaMethodID("2.7"),
            parameters: params
        )
    }

    // 2.7
    public func set(portID: OcaPortID, name: OcaString) async throws {
        let params = OcaSetPortNameParameters(portID: portID, name: name)
        try await sendCommandRrq(
            methodID: OcaMethodID("2.7"),
            parameters: params
        )
    }

    public var path: (OcaNamePath, OcaONoPath) {
        get async throws {
            try await getPath(methodID: OcaMethodID("2.13"))
        }
    }

    public func get(portID: OcaPortID) async throws -> OcaPortClockMapEntry {
        try await sendCommandRrq(
            methodID: OcaMethodID("2.16"),
            parameters: portID
        )
    }

    public typealias SetPortClockMapEntryParameters = OcaSetPortClockMapEntryParameters

    public func set(portID: OcaPortID, portClockMapEntry: OcaPortClockMapEntry) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("2.16"),
            parameters: SetPortClockMapEntryParameters(
                portID: portID,
                portClockMapEntry: portClockMapEntry
            )
        )
    }

    public func deletePortClockMapEntry(portID: OcaPortID) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("2.16"),
            parameters: portID
        )
    }
}
