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

open class OcaMediaClockManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.7") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.2")
    )
    public var clockTypesSupported = [OcaMediaClockType]()

    // 3.2 clocks is deprecated in AES70-2017 and not supported by this implementation

    // having to keep clock3Objects and clock3s in sync is not ideal, but it does mean we
    // don't have to handle event notifications ourselves
    public private(set) var clock3Objects = Set<OcaMediaClock3>()

    public func add(clock3: OcaMediaClock3) {
        clock3Objects.insert(clock3)
        clock3s.append(clock3.objectNumber)
    }

    public func remove(clock3: OcaMediaClock3) {
        clock3s.removeAll(where: { $0 == clock3.objectNumber })
        clock3Objects.remove(clock3)
    }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.3")
    )
    public private(set) var clock3s = [OcaONo]()

    public convenience init(deviceDelegate: AES70Device? = nil) async throws {
        try await self.init(
            objectNumber: OcaMediaClockManagerONo,
            role: "Media Clock Manager",
            deviceDelegate: deviceDelegate,
            addToRootBlock: false
        )
    }
}
