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
        objectNumber: OcaONo
    ) -> T? {
        if let object = objects[objectNumber] as? T {
            return object
        }

        guard let object: T = OcaClassRegistry.shared.assign(
            classIdentification: classIdentification,
            objectNumber: objectNumber
        ) else {
            return nil
        }

        add(object: object)
        return object
    }

    func resolve<T: OcaRoot>(object: OcaObjectIdentification) -> T? {
        resolve(
            classIdentification: object.classIdentification,
            objectNumber: object.oNo
        )
    }

    func resolve<T: OcaRoot>(cachedObject: OcaONo) -> T? {
        objects[cachedObject] as? T
    }

    internal func add<T: OcaRoot>(object: T) {
        objects[object.objectNumber] = object
        object.connectionDelegate = self
    }

    internal func refreshDeviceTree() async throws {
        let members = try await rootBlock.resolveActionObjectsRecursive(resolveMatrixMembers: true)
        for member in members {
            await member.memberObject._subscribeRole()
        }
    }

    @_spi(SwiftOCAPrivate)
    func getClassID(objectNumber: OcaONo) async throws -> OcaClassID {
        let command = Ocp1Command(
            commandSize: 0,
            handle: await getNextCommandHandle(),
            targetONo: objectNumber,
            methodID: OcaMethodID("1.1"),
            parameters: Ocp1Parameters()
        )
        let response = try await sendCommandRrq(command)
        guard response.statusCode == .ok else {
            throw Ocp1Error.status(response.statusCode)
        }
        guard response.parameters.parameterCount == 1 else {
            throw Ocp1Error.responseParameterOutOfRange
        }
        return try Ocp1Decoder().decode(OcaClassID.self, from: response.parameters.parameterData)
    }
}
