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

open class OcaNetworkApplication: OcaRoot {
    override public class var classID: OcaClassID { OcaClassID("1.7") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("2.1"),
        getMethodID: OcaMethodID("2.1"),
        setMethodID: OcaMethodID("2.2")
    )
    public var label: OcaProperty<OcaString>.State

    @OcaProperty(
        propertyID: OcaPropertyID("2.2"),
        getMethodID: OcaMethodID("2.3")
    )
    public var owner: OcaProperty<OcaONo>.State

    public var path: (OcaNamePath, OcaONoPath) {
        get async throws {
            let responseParams: OcaGetPathParameters
            responseParams = try await sendCommandRrq(methodID: OcaMethodID("2.4"))
            return (responseParams.namePath, responseParams.oNoPath)
        }
    }

    @OcaProperty(
        propertyID: OcaPropertyID("2.3"),
        getMethodID: OcaMethodID("2.5"),
        setMethodID: OcaMethodID("2.6")
    )
    public var networkInterfaceAssignments: OcaProperty<OcaList<OcaNetworkInterfaceAssignment>>
        .State

    @OcaProperty(
        propertyID: OcaPropertyID("2.4"),
        getMethodID: OcaMethodID("2.7")
    )
    public var adaptationIdentifier: OcaProperty<OcaAdaptationIdentifier>.State

    @OcaProperty(
        propertyID: OcaPropertyID("2.5"),
        getMethodID: OcaMethodID("2.8"),
        setMethodID: OcaMethodID("2.9")
    )
    public var adaptationData: OcaProperty<OcaAdaptationData>.State

    @OcaProperty(
        propertyID: OcaPropertyID("2.6"),
        getMethodID: OcaMethodID("2.10")
    )
    public var counterSet: OcaProperty<OcaCounterSet>.State

    // 2.11 getCounter
    // 2.12 attachCounterNotifier
    // 2.13 detachCounterNotifier
    // 2.14 resetCounters
}