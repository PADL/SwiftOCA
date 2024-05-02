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

public extension Ocp1Connection {
    private func resolve<T: OcaRoot>(
        classIdentification: OcaClassIdentification,
        objectNumber: OcaONo,
        owner: OcaONo
    ) -> T? {
        if let object = objects[objectNumber] as? T {
            if object.objectIdentification.classIdentification == classIdentification {
                return object
            }
            // allow reserved objects to be overriden by more specific subclasses
            precondition(objectNumber <= OcaMaximumReservedONo)
            precondition(
                classIdentification
                    .isSubclass(of: object.objectIdentification.classIdentification)
            )
        }

        guard let object: T = OcaClassRegistry.shared.assign(
            classIdentification: classIdentification,
            objectNumber: objectNumber
        ) else {
            return nil
        }

        if owner != OcaInvalidONo, let object = object as? OcaOwnablePrivate {
            object._set(owner: owner)
        }
        add(object: object)
        return object
    }

    func resolve<T: OcaRoot>(object: OcaObjectIdentification, owner: OcaONo = OcaInvalidONo) -> T? {
        resolve(
            classIdentification: object.classIdentification,
            objectNumber: object.oNo,
            owner: owner
        )
    }

    func resolve<T: OcaRoot>(cachedObject: OcaONo) -> T? {
        objects[cachedObject] as? T
    }

    func resolve<T: OcaRoot>(objectOfUnknownClass: OcaONo) async throws -> T? {
        if let object: T = resolve(cachedObject: objectOfUnknownClass) {
            return object
        }

        let classIdentification =
            try await getClassIdentification(objectNumber: objectOfUnknownClass)
        return resolve(object: OcaObjectIdentification(
            oNo: objectOfUnknownClass,
            classIdentification: classIdentification
        ))
    }

    internal func add<T: OcaRoot>(object: T) {
        objects[object.objectNumber] = object
        object.connectionDelegate = self
    }

    internal func refreshDeviceTree() async throws {
        let members = try await rootBlock.resolveActionObjectsRecursive()
        await withTaskGroup(of: Void.self, returning: Void.self) { taskGroup in
            for member in members {
                taskGroup.addTask {
                    // don't subscribe to role events because they are immutable, however do
                    // retrieve the initial value
                    _ = try? await member.memberObject.$role._getValue(
                        member.memberObject,
                        flags: [.returnCachedValue, .cacheValue]
                    )
                }
            }
        }
    }

    @_spi(SwiftOCAPrivate)
    func getClassIdentification(objectNumber: OcaONo) async throws -> OcaClassIdentification {
        let proxy = OcaRoot(objectNumber: objectNumber)
        proxy.connectionDelegate = self
        return try await proxy.getClassIdentification()
    }
}
