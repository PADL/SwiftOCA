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
import SwiftOCA

open class OcaMatrix: OcaWorker {
    override open class var classID: OcaClassID { OcaClassID("1.1.5") }

    @OcaVectorDeviceProperty(
        xPropertyID: OcaPropertyID("3.1"),
        yPropertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.1")
    )
    public var currentXY = OcaVector2D<OcaMatrixCoordinate>(x: 0, y: 0)

    public var members = OcaList2D<OcaRoot?>(nX: 0, nY: 0, defaultValue: nil)

    public var currentObject: OcaRoot? {
        precondition(currentXY.x < members.nX)
        precondition(currentXY.y < members.nY)

        return members[Int(currentXY.x), Int(currentXY.y)]
    }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.9"),
        setMethodID: OcaMethodID("3.10")
    )
    public var proxy: OcaONo = OcaInvalidONo

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.7"),
        getMethodID: OcaMethodID("3.11"),
        setMethodID: OcaMethodID("3.12")
    )
    public var portsPerRow: OcaUint8 = 0

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.8"),
        getMethodID: OcaMethodID("3.13"),
        setMethodID: OcaMethodID("3.14")
    )
    public var portsPerColumn: OcaUint8 = 0

    struct MatrixSize<T: Codable>: Codable {
        var xSize: T
        var ySize: T
        var minXSize: T
        var maxXSize: T
        var minYSize: T
        var maxYSize: T
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.3"):
            try ensureReadable(by: controller)
            let size = OcaVector2D<OcaMatrixCoordinate>(
                x: OcaMatrixCoordinate(members.nX),
                y: OcaMatrixCoordinate(members.nY)
            )
            let matrixSize = MatrixSize<OcaMatrixCoordinate>(
                xSize: size.x,
                ySize: size.y,
                minXSize: 0,
                maxXSize: size.x,
                minYSize: 0,
                maxYSize: size.y
            )
            return try encodeResponse(matrixSize)
        case OcaMethodID("3.5"):
            try ensureReadable(by: controller)
            let members = members.map(defaultValue: OcaInvalidONo, \.?.objectNumber)
            return try encodeResponse(members)
        case OcaMethodID("3.7"):
            try ensureReadable(by: controller)
            let coordinates: OcaVector2D<OcaMatrixCoordinate> = try decodeCommand(command)
            let objectNumber = members[Int(coordinates.x), Int(coordinates.y)]?
                .objectNumber ?? OcaInvalidONo
            return try encodeResponse(objectNumber)
        case OcaMethodID("3.8"):
            try ensureWritable(by: controller)
            struct SetMemberParameters: Codable {
                var x: OcaMatrixCoordinate
                var y: OcaMatrixCoordinate
                var memberONo: OcaONo
            }
            let parameters: SetMemberParameters = try decodeCommand(command)
            guard parameters.x < members.nX, parameters.y < members.nY else {
                throw Ocp1Error.status(.parameterOutOfRange)
            }
            let object: OcaRoot?
            if parameters.memberONo == OcaInvalidONo {
                object = nil
            } else {
                object = await deviceDelegate?.objects[parameters.memberONo]
                if object == nil {
                    throw Ocp1Error.status(.badONo)
                }
            }
            members[Int(parameters.x), Int(parameters.y)] = object
        case OcaMethodID("3.2"):
            let coordinates: OcaVector2D<OcaMatrixCoordinate> = try decodeCommand(command)
            guard coordinates.x < members.nX, coordinates.y < members.nY else {
                throw Ocp1Error.status(.parameterOutOfRange)
            }
            currentXY = coordinates
            fallthrough
        case OcaMethodID("3.15"):
            try currentObject?.lockTotal(controller: controller)
        case OcaMethodID("3.16"):
            try currentObject?.unlock(controller: controller)
        default:
            return try await super.handleCommand(command, from: controller)
        }
        return Ocp1Response()
    }

    override public var isContainer: Bool {
        true
    }
}
