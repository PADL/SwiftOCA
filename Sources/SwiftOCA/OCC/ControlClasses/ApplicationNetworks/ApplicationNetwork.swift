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

open class OcaApplicationNetwork: OcaRoot {
    override public class var classID: OcaClassID { OcaClassID("1.4") }
    override public class var classVersion: OcaClassVersionNumber { 1 }

    // FIXME: static

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

    @OcaProperty(
        propertyID: OcaPropertyID("2.3"),
        getMethodID: OcaMethodID("2.4"),
        setMethodID: OcaMethodID("2.5")
    )
    public var serviceID: OcaProperty<OcaApplicationNetworkServiceID>.State

    @OcaProperty(
        propertyID: OcaPropertyID("2.4"),
        getMethodID: OcaMethodID("2.6"),
        setMethodID: OcaMethodID("2.7")
    )
    public var systemInterfaces: OcaProperty<OcaList<OcaNetworkSystemInterfaceDescriptor>>.State

    @OcaProperty(
        propertyID: OcaPropertyID("2.5"),
        getMethodID: OcaMethodID("2.8")
    )
    public var state: OcaProperty<OcaApplicationNetworkState>.State

    @OcaProperty(
        propertyID: OcaPropertyID("2.6"),
        getMethodID: OcaMethodID("2.8")
    )
    public var errorCode: OcaProperty<OcaUint16>.State

    var path: (OcaNamePath, OcaONoPath) {
        get async throws {
            let responseParams: OcaGetPathParameters

            responseParams = try await sendCommandRrq(methodID: OcaMethodID("2.11"))

            return (responseParams.namePath, responseParams.oNoPath)
        }
    }

    func control(_ command: OcaApplicationNetworkCommand) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("2.10"),
            parameters: command
        )
    }
}
