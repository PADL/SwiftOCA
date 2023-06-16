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
import Combine

public struct OcaBlockMember: Codable {
    let memberObjectIdentification: OcaObjectIdentification
    let containerObjectNumber: OcaONo
}

public class OcaBlock: OcaWorker {
    public override class var classID: OcaClassID { OcaClassID("1.1.3") }
    
    @OcaProperty(propertyID: OcaPropertyID("3.1"),
                 getMethodID: OcaMethodID("3.1"))
    public var type: OcaProperty<OcaONo>.State
    
    @OcaProperty(propertyID: OcaPropertyID("3.2"),
                 getMethodID: OcaMethodID("3.5"))
    public var members: OcaProperty<OcaList<OcaObjectIdentification>>.State
    
    @OcaProperty(propertyID: OcaPropertyID("3.3"),
                 getMethodID: OcaMethodID("3.16"))
    public var signalPaths: OcaProperty<OcaMap<OcaUint16, OcaSignalPath>>.State
    
    @OcaProperty(propertyID: OcaPropertyID("3.4"),
                 getMethodID: OcaMethodID("3.11"))
    public var mostRecentParamSetIdentifier: OcaProperty<OcaLibVolIdentifier>.State
    
    @OcaProperty(propertyID: OcaPropertyID("3.5"),
                 getMethodID: OcaMethodID("3.15"))
    public var globalType: OcaProperty<OcaGlobalTypeIdentifier>.State
    
    @OcaProperty(propertyID: OcaPropertyID("3.6"),
                 getMethodID: OcaMethodID("3.16"))
    public var oNoMap: OcaProperty<OcaMap<OcaProtoONo, OcaONo>>.State
    
    // 3.2
    func constructMember(classID: OcaClassID,
                         constructionParameters: [any Codable],
                         objectNumber: inout OcaONo) async throws {
        throw Ocp1Error.status(.notImplemented)
    }
    
    // 3.3
    func constructMember(factory factoryONo: OcaONo,
                         objectNumber: inout OcaONo) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.3"),
                                 parameter: factoryONo,
                                 responseParameterCount: 1, responseParameters: &objectNumber)
    }
    
    // 3.4
    func delete(member objectNumber: OcaONo) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.4"),
                                 parameter: objectNumber)
    }
    
    // 3.7
    func getRecursive(members: inout OcaList<OcaBlockMember>) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.6"),
                                 responseParameterCount: 1,
                                 responseParameters: &members)
    }
    
    // 3.7
    func add(signalPath path: OcaSignalPath, index: inout OcaUint16) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.7"),
                                 parameter: path,
                                 responseParameterCount: 1,
                                 responseParameters: &index)
    }
    
    // 3.8
    func delete(signalPath index: OcaUint16) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.8"),
                                 parameter: index)
    }
    
    // 3.10
    func getRecursive(signalPaths members: inout OcaMap<OcaUint16, OcaSignalPath>) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.10"),
                                 responseParameterCount: 1,
                                 responseParameters: &members)
    }
    
    // 3.12
    func apply(paramSet identifier: OcaLibVolIdentifier) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.12"),
                                 parameter: identifier)
    }
    
    // 3.13
    func get(currentParamSet paramSet: inout OcaLibVolData_ParamSet) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.13"),
                                 responseParameterCount: 1,
                                 responseParameters: &paramSet)
    }
    
    // 3.14
    func store(currentParamSet identifier: OcaLibVolIdentifier) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.14"),
                                 parameter: identifier)
    }
    
    struct FindObjectsByRoleParameters: Codable {
        let searchName: OcaString
        let nameComparisonType: OcaStringComparisonType
        let searchClassID: OcaClassID
        let resultFlags: OcaObjectSearchResultFlags
    }
    
    // 3.17
    func find(objectsByRole searchName: OcaString,
              nameComparisonType: OcaStringComparisonType,
              searchClassID: OcaClassID,
              resultFlags: OcaObjectSearchResultFlags,
              result: inout OcaList<OcaObjectSearchResult>) async throws {
        let params = FindObjectsByRoleParameters(searchName: searchName,
                                                 nameComparisonType: nameComparisonType,
                                                 searchClassID: searchClassID,
                                                 resultFlags: resultFlags)
        
        try await sendCommandRrq(methodID: OcaMethodID("3.17"),
                                 parameters: params,
                                 responseParameterCount: 1,
                                 responseParameters: &result)
    }
    
    // 3.18
    func findRecursive(objectsByRole searchName: OcaString,
                       nameComparisonType: OcaStringComparisonType,
                       searchClassID: OcaClassID,
                       resultFlags: OcaObjectSearchResultFlags,
                       result: inout OcaList<OcaObjectSearchResult>) async throws {
        let params = FindObjectsByRoleParameters(searchName: searchName,
                                                 nameComparisonType: nameComparisonType,
                                                 searchClassID: searchClassID,
                                                 resultFlags: resultFlags)
        
        try await sendCommandRrq(methodID: OcaMethodID("3.18"),
                                 parameters: params,
                                 responseParameterCount: 1,
                                 responseParameters: &result)
    }
    
    // 3.19
    func find(objectsByPath searchPath: OcaString,
              resultFlags: OcaObjectSearchResultFlags,
              result: inout OcaList<OcaObjectSearchResult>) async throws {
        throw Ocp1Error.status(.notImplemented)
    }
    
    // 3.20
    func findRecursive(objectsByLabel searchName: OcaString,
                       nameComparisonType: OcaStringComparisonType,
                       searchClassID: OcaClassID,
                       resultFlags: OcaObjectSearchResultFlags,
                       result: inout OcaList<OcaObjectSearchResult>) async throws {
        throw Ocp1Error.status(.notImplemented)
    }
}

extension OcaBlock {
    @MainActor
    func resolveMembers() async throws -> OcaList<OcaRoot> {
        guard let connectionDelegate else { throw Ocp1Error.notConnected }

        return try await self._members.onCompletion { members in
            members.compactMap { connectionDelegate.resolve(object: $0) }
        }
    }
}
