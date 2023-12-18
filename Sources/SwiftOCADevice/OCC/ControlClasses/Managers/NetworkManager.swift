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

import SwiftOCA

open class OcaNetworkManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.6") }

    // networks and streamNetworks are deprecated

    public private(set) var controlNetworkObjects = Set<OcaControlNetwork>()

    public func add(controlNetwork: OcaControlNetwork) {
        controlNetworkObjects.insert(controlNetwork)
        controlNetworks.append(controlNetwork.objectNumber)
    }

    public func remove(controlNetwork: OcaControlNetwork) {
        controlNetworks.removeAll(where: { $0 == controlNetwork.objectNumber })
        controlNetworkObjects.remove(controlNetwork)
    }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.3")
    )
    public private(set) var controlNetworks = [OcaONo]()

    public private(set) var mediaTransportNetworkObjects = Set<OcaMediaTransportNetwork>()

    public func add(mediaTransportNetwork: OcaMediaTransportNetwork) {
        mediaTransportNetworkObjects.insert(mediaTransportNetwork)
        mediaTransportNetworks.append(mediaTransportNetwork.objectNumber)
    }

    public func remove(mediaTransportNetwork: OcaMediaTransportNetwork) {
        mediaTransportNetworks.removeAll(where: { $0 == mediaTransportNetwork.objectNumber })
        mediaTransportNetworkObjects.remove(mediaTransportNetwork)
    }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.4")
    )
    public private(set) var mediaTransportNetworks = [OcaONo]()

    public convenience init(deviceDelegate: AES70Device? = nil) async throws {
        try await self.init(
            objectNumber: OcaNetworkManagerONo,
            role: "Network Manager",
            deviceDelegate: deviceDelegate,
            addToRootBlock: true
        )
    }
}
