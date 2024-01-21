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

    // 2.3
    public func add(
        port label: OcaString,
        mode: OcaPortMode,
        portID: inout OcaPortID
    ) async throws {
        struct AddPortParameters: Codable {
            let label: OcaString
            let mode: OcaPortMode
        }
        let params = AddPortParameters(label: label, mode: mode)
        try await sendCommandRrq(
            methodID: OcaMethodID("2.3"),
            parameters: params,
            responseParameterCount: 1,
            responseParameters: &portID
        )
    }

    // 2.4
    public func delete(port id: OcaPortID) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("2.4"),
            parameter: id
        )
    }

    // 2.6
    public func get(portID: OcaPortID, name: inout OcaString) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("2.7"),
            parameter: portID,
            responseParameterCount: 1,
            responseParameters: &name
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
}
