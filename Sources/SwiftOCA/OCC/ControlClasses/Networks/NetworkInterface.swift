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

open class OcaNetworkInterface: OcaRoot, OcaOwnablePrivate {
    override public class var classID: OcaClassID { OcaClassID("1.6") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("2.1"),
        getMethodID: OcaMethodID("2.1"),
        setMethodID: OcaMethodID("2.2")
    )
    public var label: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.2"),
        getMethodID: OcaMethodID("2.3")
    )
    public var owner: OcaProperty<OcaONo>.PropertyValue

    public var path: (OcaNamePath, OcaONoPath) {
        get async throws {
            try await getPath(methodID: OcaMethodID("2.4"))
        }
    }

    @OcaProperty(
        propertyID: OcaPropertyID("2.3"),
        getMethodID: OcaMethodID("2.5"),
        setMethodID: OcaMethodID("2.6")
    )
    public var enabled: OcaProperty<OcaBoolean>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.4"),
        getMethodID: OcaMethodID("2.7"),
        setMethodID: OcaMethodID("2.8")
    )
    public var systemIOInterfaceName: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.5"),
        getMethodID: OcaMethodID("2.9"),
        setMethodID: OcaMethodID("2.10")
    )
    public var groupID: OcaProperty<OcaUint16>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.6"),
        getMethodID: OcaMethodID("2.11"),
        setMethodID: OcaMethodID("2.12")
    )
    public var precedence: OcaProperty<OcaUint16>.PropertyValue

    // "OcaIP4" or "OcaIP6"
    @OcaProperty(
        propertyID: OcaPropertyID("2.7"),
        getMethodID: OcaMethodID("2.13")
    )
    public var adaptationIdentifier: OcaProperty<OcaAdaptationIdentifier>.PropertyValue

    // encoded OcaIP4NetworkSettings or OcaIP6NetworkSettings
    @OcaProperty(
        propertyID: OcaPropertyID("2.8"),
        getMethodID: OcaMethodID("2.14"),
        setMethodID: OcaMethodID("2.15")
    )
    public var activeNetworkSettings: OcaProperty<OcaBlob>.PropertyValue

    // encoded OcaIP4NetworkSettings or OcaIP6NetworkSettings
    @OcaProperty(
        propertyID: OcaPropertyID("2.9"),
        getMethodID: OcaMethodID("2.15"),
        setMethodID: OcaMethodID("2.16")
    )
    public var targetNetworkSettings: OcaProperty<OcaBlob>.PropertyValue

    // encoded OcaIP4NetworkSettings or OcaIP6NetworkSettings
    @OcaProperty(
        propertyID: OcaPropertyID("2.10"),
        getMethodID: OcaMethodID("2.17")
    )
    public var networkSettingPending: OcaProperty<OcaBoolean>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.11"),
        getMethodID: OcaMethodID("2.18")
    )
    public var status: OcaProperty<OcaNetworkInterfaceStatus>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.12"),
        getMethodID: OcaMethodID("2.19")
    )
    public var errorCode: OcaProperty<OcaUint16>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("2.13"),
        getMethodID: OcaMethodID("2.20")
    )
    public var counterSet: OcaProperty<OcaCounterSet>.PropertyValue

    // 2.21 getCounter
    // 2.22 attachCounterNotifier
    // 2.23 detachCounterNotifier
    // 2.24 resetCounters
    // 2.25 applyComment
}

extension OcaNetworkInterface {
    @_spi(SwiftOCAPrivate)
    public func _getOwner(flags: OcaPropertyResolutionFlags = .defaultFlags) async throws
        -> OcaONo
    {
        guard objectNumber != OcaRootBlockONo else { throw Ocp1Error.status(.invalidRequest) }
        return try await $owner._getValue(self, flags: flags)
    }

    func _set(owner: OcaONo) {
        self.$owner.subject.send(.success(owner))
    }
}
