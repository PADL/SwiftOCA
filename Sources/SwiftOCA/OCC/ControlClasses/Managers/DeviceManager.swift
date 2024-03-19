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

public enum OcaResetCause: OcaUint8, Sendable, Codable, CaseIterable {
    case powerOn = 0
    case internalError = 1
    case upgrade = 2
    case externalRequest = 3
}

open class OcaDeviceManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.1") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.2")
    )
    public var modelGUID: OcaProperty<OcaModelGUID>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.3")
    )
    public var serialNumber: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.6")
    )
    public var modelDescription: OcaProperty<OcaModelDescription>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.4"),
        setMethodID: OcaMethodID("3.5")
    )
    public var deviceName: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.1")
    )
    public var version: OcaProperty<OcaUint16>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.7"),
        setMethodID: OcaMethodID("3.8")
    )
    public var deviceRole: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.7"),
        getMethodID: OcaMethodID("3.9"),
        setMethodID: OcaMethodID("3.10")
    )
    public var userInventoryCode: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.8"),
        getMethodID: OcaMethodID("3.11"),
        setMethodID: OcaMethodID("3.12")
    )
    public var enabled: OcaProperty<OcaBoolean>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.9"),
        getMethodID: OcaMethodID("3.13")
    )
    public var state: OcaProperty<OcaDeviceState>.PropertyValue

    @OcaProperty(propertyID: OcaPropertyID("3.10"))
    public var busy: OcaProperty<OcaBoolean>.PropertyValue

    // 3.14
    public func setResetKey(key: OcaBlob, address: OcaNetworkAddress) async throws {
        // TODO: constrain key to 16 bytes
        throw Ocp1Error.notImplemented
    }

    @OcaProperty(
        propertyID: OcaPropertyID("3.11"),
        getMethodID: OcaMethodID("3.15")
    )
    public var resetCause: OcaProperty<OcaResetCause>.PropertyValue

    // 3.16
    public func clearResetCause() async throws {
        throw Ocp1Error.notImplemented
    }

    @OcaProperty(
        propertyID: OcaPropertyID("3.12"),
        getMethodID: OcaMethodID("3.17"),
        setMethodID: OcaMethodID("3.18")
    )
    public var message: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.13"),
        getMethodID: OcaMethodID("3.19")
    )
    public var managers: OcaListProperty<OcaManagerDescriptor>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.14"),
        getMethodID: OcaMethodID("3.20")
    )
    public var deviceRevisionID: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.15"),
        getMethodID: OcaMethodID("3.21")
    )
    public var manufacturer: OcaProperty<OcaManufacturer>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.16"),
        getMethodID: OcaMethodID("3.22")
    )
    public var product: OcaProperty<OcaProduct>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.17"),
        getMethodID: OcaMethodID("3.23")
    )
    public var operationalState: OcaProperty<OcaDeviceOperationalState>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.18"),
        getMethodID: OcaMethodID("3.24"),
        setMethodID: OcaMethodID("3.25")
    )
    public var loggingEnabled: OcaProperty<OcaBoolean>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.19"),
        getMethodID: OcaMethodID("3.26")
    )
    public var mostRecentPatchDatasetONo: OcaProperty<OcaONo>.PropertyValue

    convenience init() {
        self.init(objectNumber: OcaDeviceManagerONo)
    }

    public func applyPatch(datasetONo: OcaONo) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.27"), parameters: datasetONo)
    }
}
