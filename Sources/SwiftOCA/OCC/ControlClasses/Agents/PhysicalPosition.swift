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

public enum OcaPositionCoordinateSystem: OcaUint8, Codable {
    case robotic = 1
    case ituAudioObjectBasedPolar = 2
    case ituAudioObjectBasedCartesian = 3
    case ituAudioSceneBasedPolar = 4
    case ituAudioSceneBasedCartesian = 5
    case nav = 6
    case proprietaryBase = 128
}

public struct OcaPositionDescriptorFieldFlags: OptionSet, Codable {
    public let rawValue: OcaBitSet16

    public init(rawValue: OcaBitSet16) {
        self.rawValue = rawValue
    }
}

public struct OcaPositionDescriptor: Codable, Comparable {
    public static func < (lhs: OcaPositionDescriptor, rhs: OcaPositionDescriptor) -> Bool {
        guard lhs.coordinateSystem == rhs.coordinateSystem else {
            return false
        }
        // FIXME: check fieldFlags
        return lhs.values.0 < rhs.values.0 &&
            lhs.values.1 < rhs.values.1 &&
            lhs.values.2 < rhs.values.2 &&
            lhs.values.3 < rhs.values.3 &&
            lhs.values.4 < rhs.values.4 &&
            lhs.values.5 < rhs.values.5
    }

    public static func == (lhs: OcaPositionDescriptor, rhs: OcaPositionDescriptor) -> Bool {
        lhs.coordinateSystem == rhs.coordinateSystem &&
            lhs.fieldFlags == rhs.fieldFlags &&
            lhs.values == rhs.values
    }

    let coordinateSystem: OcaPositionCoordinateSystem
    let fieldFlags: OcaPositionDescriptorFieldFlags // which values are valid
    let values: (OcaFloat32, OcaFloat32, OcaFloat32, OcaFloat32, OcaFloat32, OcaFloat32)

    enum CodingKeys: CodingKey {
        case coordinateSystem
        case fieldFlags
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coordinateSystem = try container.decode(
            OcaPositionCoordinateSystem.self,
            forKey: .coordinateSystem
        )
        fieldFlags = try container.decode(OcaPositionDescriptorFieldFlags.self, forKey: .fieldFlags)
        var coordinateContainer = try container.nestedUnkeyedContainer(forKey: .values)
        values.0 = try coordinateContainer.decode(OcaFloat32.self)
        values.1 = try coordinateContainer.decode(OcaFloat32.self)
        values.2 = try coordinateContainer.decode(OcaFloat32.self)
        values.3 = try coordinateContainer.decode(OcaFloat32.self)
        values.4 = try coordinateContainer.decode(OcaFloat32.self)
        values.5 = try coordinateContainer.decode(OcaFloat32.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinateSystem, forKey: .coordinateSystem)
        try container.encode(fieldFlags, forKey: .fieldFlags)
        var coordinateContainer = container.nestedUnkeyedContainer(forKey: .values)
        try coordinateContainer.encode(values.0)
        try coordinateContainer.encode(values.1)
        try coordinateContainer.encode(values.2)
        try coordinateContainer.encode(values.3)
        try coordinateContainer.encode(values.4)
        try coordinateContainer.encode(values.5)
    }
}

open class OcaPhysicalPosition: OcaAgent {
    override public class var classID: OcaClassID { OcaClassID("1.2.17") }

    override public class var classVersion: OcaClassVersionNumber { 1 }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var coordinateSystem: OcaProperty<OcaPositionCoordinateSystem>.State

    @OcaProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.2")
    )
    public var positionDescriptorFieldFlags: OcaProperty<OcaPositionDescriptorFieldFlags>.State

    @OcaProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.3"),
        setMethodID: OcaMethodID("3.4")
    )
    public var positionDescriptor: OcaBoundedProperty<OcaPositionDescriptor>.State
}
