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

public typealias OcaMatrixCoordinate = OcaUint16

open class OcaMatrix: OcaWorker {
    override open class var classID: OcaClassID { OcaClassID("1.1.5") }

    @OcaVectorProperty(
        xPropertyID: OcaPropertyID("3.1"),
        yPropertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.1"),
        setMethodID: OcaMethodID("3.2")
    )
    public var currentXY: OcaVectorProperty<OcaMatrixCoordinate>.State

    // TODO: GetSize() also returns min/max size which hopefully we can ignore

    @OcaVectorProperty(
        xPropertyID: OcaPropertyID("3.3"),
        yPropertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.3"),
        setMethodID: OcaMethodID("3.4")
    )
    public var size: OcaVectorProperty<OcaMatrixCoordinate>.State

    @OcaProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.5"),
        setMethodID: OcaMethodID("3.6")
    )
    public var members: OcaProperty<OcaList2D<OcaONo>>.State

    @OcaProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.9"),
        setMethodID: OcaMethodID("3.10")
    )
    public var proxy: OcaProperty<OcaONo>.State

    @OcaProperty(
        propertyID: OcaPropertyID("3.7"),
        getMethodID: OcaMethodID("3.11"),
        setMethodID: OcaMethodID("3.12")
    )
    public var portsPerRow: OcaProperty<OcaUint8>.State

    @OcaProperty(
        propertyID: OcaPropertyID("3.8"),
        getMethodID: OcaMethodID("3.13"),
        setMethodID: OcaMethodID("3.14")
    )
    public var portsPerColumn: OcaProperty<OcaUint8>.State

    func get(x: OcaMatrixCoordinate, y: OcaMatrixCoordinate) async throws -> OcaONo {
        let xy = OcaVector2D(x: x, y: y)
        return try await sendCommandRrq(methodID: OcaMethodID("3.7"), parameters: xy)
    }

    func set(x: OcaMatrixCoordinate, y: OcaMatrixCoordinate, memberONo: OcaONo) async throws {
        struct SetMemberParameters: Codable {
            var xy: OcaVector2D<OcaMatrixCoordinate> // this is really two separate parameters,
            // hence parameterCount
            var memberONo: OcaONo
        }
        let xy = OcaVector2D(x: x, y: y)
        try await sendCommandRrq(
            methodID: OcaMethodID("3.8"),
            parameterCount: 3,
            parameters: SetMemberParameters(xy: xy, memberONo: memberONo)
        )
    }

    func lockCurrent(x: OcaMatrixCoordinate, y: OcaMatrixCoordinate) async throws {
        let xy = OcaVector2D(x: x, y: y)
        try await sendCommandRrq(methodID: OcaMethodID("3.15"), parameter: xy)
    }

    func unlockCurrent() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.16"))
    }

    override public var isContainer: Bool {
        true
    }
}

public extension OcaMatrix {
    /// resolve members using proxy class, members are optional as some may be unset

    typealias SparseMembers = OcaList2D<OcaRoot?>

    @MainActor
    func resolveMembers() async throws -> SparseMembers {
        let proxy = try await resolveProxy()
        return try await resolveMembers(with: proxy)
    }

    @MainActor
    func resolveMembers(with proxy: OcaRoot) async throws -> SparseMembers {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        return try await _members.onCompletion(self) { value in
            var resolved = SparseMembers(nX: value.nX, nY: value.nY, defaultValue: nil)
            let proxyClassID = type(of: proxy).classIdentification

            for x in 0..<value.nX {
                for y in 0..<value.nY {
                    let objectID = OcaObjectIdentification(
                        oNo: value[x, y],
                        classIdentification: proxyClassID
                    )
                    resolved[x, y] = connectionDelegate.resolve(object: objectID)
                }
            }

            return resolved
        }
    }

    @MainActor
    func resolveProxy<T: OcaRoot>() async throws -> T {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        return try await _proxy.onCompletion(self) { proxyObjectNumber in
            let unresolvedProxy = OcaRoot(objectNumber: proxyObjectNumber)
            unresolvedProxy.connectionDelegate = self.connectionDelegate
            var classIdentification = OcaRoot.classIdentification
            try await unresolvedProxy.get(classIdentification: &classIdentification)
            let objectID = OcaObjectIdentification(
                oNo: unresolvedProxy.objectNumber,
                classIdentification: classIdentification
            )
            let resolvedProxy = connectionDelegate.resolve(object: objectID) as? T
            guard let resolvedProxy else {
                throw Ocp1Error.proxyResolutionFailed
            }
            return resolvedProxy
        }
    }
}

public extension OcaList2D where Element == OcaRoot? {
    var hasContainerMembers: Bool {
        items.allSatisfy { $0?.isContainer ?? false }
    }
}
