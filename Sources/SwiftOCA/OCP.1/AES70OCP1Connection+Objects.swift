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

extension AES70OCP1Connection {
    @MainActor
    private func resolve<T: OcaRoot>(classIdentification: OcaClassIdentification,
                                     objectNumber: OcaONo) -> T? {
        if let object = objects[objectNumber] as? T {
            return object
        }
        
        guard let object: T = AES70ClassRegistry.shared.assign(classIdentification: classIdentification,
                                                               objectNumber: objectNumber) else {
            return nil
        }
     
        add(object: object)
        return object
    }
    
    @MainActor
    public func resolve<T: OcaRoot>(object: OcaObjectIdentification) -> T? {
        return resolve(classIdentification: object.classIdentification,
                       objectNumber: object.oNo)
    }
    
    @MainActor
    func add<T: OcaRoot>(object: T) {
        objects[object.objectNumber] = object
        object.connectionDelegate = self
    }
        
    @MainActor
    func refreshDeviceTree() async throws {
        let members = try await rootBlock.resolveMembersRecursive(resolveMatrixMembers: true)
        Task {
            for member in members {
                await member.memberObject.$role.subscribe(member.memberObject)
            }
        }
    }
}
