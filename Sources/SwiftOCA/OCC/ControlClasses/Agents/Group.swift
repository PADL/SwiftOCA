//
// Copyright (c) 2024 PADL Software Pty Ltd
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

open class OcaGroup: OcaAgent {
    override public class var classID: OcaClassID { OcaClassID("1.2.22") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1"),
        setMethodID: OcaMethodID("3.2")
    )
    public var members: OcaListProperty<OcaONo>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.5"),
        setMethodID: OcaMethodID("3.6")
    )
    public var groupController: OcaProperty<OcaONo>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.7"),
        setMethodID: OcaMethodID("3.8")
    )
    public var aggregationMode: OcaProperty<OcaString?>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.9"),
        setMethodID: OcaMethodID("3.10")
    )
    public var saturationMode: OcaProperty<OcaString?>.PropertyValue

    public func add(member objectNumber: OcaONo) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.3"),
            parameters: objectNumber
        )
    }

    public func delete(member objectNumber: OcaONo) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.4"),
            parameters: objectNumber
        )
    }
}

public extension OcaGroup {
    @OcaConnection
    func resolveMembers<T: OcaRoot>() async throws -> [T] {
        let groupController = try await resolveGroupController()
        return try await resolveMembers(with: groupController)
    }

    @OcaConnection
    func resolveMembers<T: OcaRoot>(with groupController: OcaRoot) async throws -> [T] {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        return try await _members.onCompletion(self) { members in
            var resolved = [T]()
            let groupControllerClassID = type(of: groupController).classIdentification

            for member in members {
                let objectID = OcaObjectIdentification(
                    oNo: member,
                    classIdentification: groupControllerClassID
                )
                guard let member = await connectionDelegate.resolve(object: objectID) as? T
                else {
                    throw Ocp1Error.invalidObject(member)
                }
                resolved.append(member)
            }

            return resolved
        }
    }

    @OcaConnection
    func resolveGroupController<T: OcaRoot>() async throws -> T {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        return try await _groupController.onCompletion(self) { groupControllerObjectNumber in
            let classIdentification = try await connectionDelegate
                .getClassIdentification(objectNumber: groupControllerObjectNumber)
            let objectID = OcaObjectIdentification(
                oNo: groupControllerObjectNumber,
                classIdentification: classIdentification
            )
            let resolvedProxy = await connectionDelegate.resolve(object: objectID) as? T
            guard let resolvedProxy else {
                throw Ocp1Error.proxyResolutionFailed
            }
            return resolvedProxy
        }
    }
}
