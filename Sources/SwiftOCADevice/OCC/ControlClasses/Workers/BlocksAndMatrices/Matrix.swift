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

private struct OcaMatrixSetMemberParameters: Codable {
    var x: OcaMatrixCoordinate
    var y: OcaMatrixCoordinate
    var memberONo: OcaONo
}

open class OcaMatrix<Member: OcaRoot>: OcaWorker {
    override open class var classID: OcaClassID { OcaClassID("1.1.5") }

    public private(set) var proxy: Proxy<Member>!
    private var lockStatePriorToSetCurrentXY: LockState?

    override public init(
        objectNumber: OcaONo? = nil,
        lockable: OcaBoolean = true,
        role: OcaString = "Matrix",
        deviceDelegate: AES70OCP1Device? = nil,
        addToRootBlock: Bool = true
    ) async throws {
        try await super.init(
            objectNumber: objectNumber,
            lockable: lockable,
            role: role,
            deviceDelegate: deviceDelegate,
            addToRootBlock: addToRootBlock
        )
        proxy = try await Proxy<Member>(self)
    }

    public class Proxy<Member: OcaRoot>: OcaRoot {
        weak var matrix: OcaMatrix?

        override public class var classIdentification: OcaClassIdentification {
            Member.classIdentification
        }

        public init(
            _ matrix: OcaMatrix
        ) async throws {
            try await super.init(
                lockable: matrix.lockable,
                role: "\(matrix) Proxy",
                deviceDelegate: matrix.deviceDelegate,
                addToRootBlock: false
            )
        }

        override open func handleCommand(
            _ command: Ocp1Command,
            from controller: AES70OCP1Controller
        ) async throws -> Ocp1Response {
            var response: Ocp1Response!
            var lastStatus: OcaStatus?

            defer { try? matrix?.unlockSelfAndProxy(controller: controller) }

            try await matrix?.withCurrentObject { object in
                do {
                    if response != nil, response.parameters.parameterCount > 0 {
                        // multiple get requests aren't supported
                        throw Ocp1Error.status(.invalidRequest)
                    }
                    response = try await object.handleCommand(command, from: controller)
                    if lastStatus != .ok {
                        lastStatus = .partiallySucceeded
                    }
                } catch let Ocp1Error.status(status) {
                    if lastStatus == .ok {
                        lastStatus = .partiallySucceeded
                    } else if lastStatus != status {
                        lastStatus = .processingFailed
                    } else {
                        lastStatus = status
                    }
                }
            }

            guard let lastStatus else {
                throw Ocp1Error.status(.badONo)
            }

            guard lastStatus == .ok else {
                throw Ocp1Error.status(lastStatus)
            }

            return response
        }
    }

    private func lockSelfAndProxy(controller: AES70OCP1Controller) throws {
        guard lockable else { return }

        switch lockState {
        case .unlocked:
            lockStatePriorToSetCurrentXY = .unlocked
            lockState = .lockedNoReadWrite(controller)
        case let .lockedNoWrite(lockholder):
            fallthrough
        case let .lockedNoReadWrite(lockholder):
            guard controller == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            lockStatePriorToSetCurrentXY = lockState
            lockState = .lockedNoReadWrite(controller)
        }
        proxy.lockState = lockState
    }

    fileprivate func unlockSelfAndProxy(controller: AES70OCP1Controller) throws {
        guard lockable else { return }

        guard let lockStatePriorToSetCurrentXY else {
            throw Ocp1Error.status(.invalidRequest)
        }

        switch lockState {
        case .unlocked:
            throw Ocp1Error.status(.invalidRequest)
        case let .lockedNoWrite(lockholder):
            fallthrough
        case let .lockedNoReadWrite(lockholder):
            guard controller == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            lockState = lockStatePriorToSetCurrentXY
            proxy.lockState = lockStatePriorToSetCurrentXY
            self.lockStatePriorToSetCurrentXY = nil
        }
    }

    @OcaVectorDeviceProperty(
        xPropertyID: OcaPropertyID("3.1"),
        yPropertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.1")
    )
    public var currentXY = OcaVector2D<OcaMatrixCoordinate>(x: 0, y: 0)

    public var members = OcaList2D<OcaRoot?>(nX: 0, nY: 0, defaultValue: nil)

    open func add(member object: Member, at coordinate: OcaVector2D<OcaMatrixCoordinate>) throws {
        precondition(object != self)
        guard coordinate.isValid(in: self) else {
            throw Ocp1Error.status(.parameterOutOfRange)
        }
        if let object = object as? OcaWorker {
            object.owner = objectNumber
        }
        members.insert(object, x: Int(coordinate.x), y: Int(coordinate.y))
    }

    open func remove(coordinate: OcaVector2D<OcaMatrixCoordinate>) throws {
        guard coordinate.isValid(in: self) else {
            throw Ocp1Error.status(.parameterOutOfRange)
        }
        if let object = members[Int(coordinate.x), Int(coordinate.y)] as? OcaWorker,
           object.owner == objectNumber
        {
            object.owner = OcaInvalidONo
        }
        members.remove(x: Int(coordinate.x), y: Int(coordinate.y))
    }

    func withCurrentObject(_ body: (_ object: OcaRoot) async throws -> ()) async rethrows {
        if currentXY.x == 0xFFFF && currentXY.y == 0xFFFF {
            for object in members.items {
                if let object { try await body(object) }
            }
        } else if currentXY.x == 0xFFFF {
            for x in 0..<members.nX {
                if let object = members[x, Int(currentXY.y)] { try await body(object) }
            }
        } else if currentXY.y == 0xFFFF {
            for y in 0..<members.nY {
                if let object = members[Int(currentXY.x), y] { try await body(object) }
            }
        } else {
            precondition(currentXY.x < members.nX)
            precondition(currentXY.y < members.nY)

            if let object = members[Int(currentXY.x), Int(currentXY.y)] {
                try await body(object)
            }
        }
    }

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
            try await ensureReadable(by: controller)
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
            try await ensureReadable(by: controller)
            let members = members.map(defaultValue: OcaInvalidONo, \.?.objectNumber)
            return try encodeResponse(members)
        case OcaMethodID("3.7"):
            try await ensureReadable(by: controller)
            let coordinates: OcaVector2D<OcaMatrixCoordinate> = try decodeCommand(command)
            let objectNumber = members[Int(coordinates.x), Int(coordinates.y)]?
                .objectNumber ?? OcaInvalidONo
            return try encodeResponse(objectNumber)
        case OcaMethodID("3.8"):
            try await ensureWritable(by: controller)
            let parameters: OcaMatrixSetMemberParameters = try decodeCommand(command)
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
        case OcaMethodID("3.9"):
            try await ensureReadable(by: controller)
            return try encodeResponse(proxy.objectNumber)
        case OcaMethodID("3.2"):
            try await ensureWritable(by: controller)
            let coordinates: OcaVector2D<OcaMatrixCoordinate> = try decodeCommand(command)
            guard coordinates.x < members.nX || coordinates.x == 0xFFFF,
                  coordinates.y < members.nY || coordinates.y == 0xFFFF
            else {
                throw Ocp1Error.status(.parameterOutOfRange)
            }
            currentXY = coordinates
            try lockSelfAndProxy(controller: controller)
            fallthrough
        case OcaMethodID("3.15"):
            try await withCurrentObject { try $0.lockNoReadWrite(controller: controller) }
        case OcaMethodID("3.16"):
            try await withCurrentObject { try $0.unlock(controller: controller) }
        default:
            return try await super.handleCommand(command, from: controller)
        }
        return Ocp1Response()
    }

    override public var isContainer: Bool {
        true
    }
}

extension OcaVector2D where T == OcaMatrixCoordinate {
    func isValid<Member: OcaRoot>(in matrix: OcaMatrix<Member>) -> Bool {
        x != 0xFFFF && x < matrix.members.nX &&
            y != 0xFFFF && y < matrix.members.nY
    }
}
