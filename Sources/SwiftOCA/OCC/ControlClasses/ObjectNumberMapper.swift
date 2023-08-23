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

public protocol OcaObjectNumberMapper {
    func map(localObjectNumber: OcaONo) async throws -> OcaONo
    func map(remoteObjectNumber: OcaONo) async throws -> OcaONo
}

class OcaIdentityObjectNumberMapper: OcaObjectNumberMapper {
    static var shared = OcaIdentityObjectNumberMapper()

    func map(localObjectNumber: OcaONo) async throws -> OcaONo {
        localObjectNumber
    }

    func map(remoteObjectNumber: OcaONo) async throws -> OcaONo {
        remoteObjectNumber
    }
}

extension OcaObjectNumberMapper {
    func map(localObjectIdentification: OcaObjectIdentification) async throws
        -> OcaObjectIdentification
    {
        OcaObjectIdentification(
            oNo: try await map(localObjectNumber: localObjectIdentification.oNo),
            classIdentification: localObjectIdentification.classIdentification
        )
    }

    func map(remoteObjectIdentification: OcaObjectIdentification) async throws
        -> OcaObjectIdentification
    {
        OcaObjectIdentification(
            oNo: try await map(remoteObjectNumber: remoteObjectIdentification.oNo),
            classIdentification: remoteObjectIdentification.classIdentification
        )
    }
}
