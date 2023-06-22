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

public struct OcaBlockMember: Codable {
    let memberObjectIdentification: OcaObjectIdentification
    let containerObjectNumber: OcaONo
}

public struct OcaContainerObjectMember {
    let memberObject: OcaRoot
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
                         constructionParameters: [any Codable]) async throws -> OcaONo {
        throw Ocp1Error.notImplemented
    }
    
    func constructMember(factory factoryONo: OcaONo) async throws -> OcaONo {
        try await sendCommandRrq(methodID: OcaMethodID("3.3"),
                                 parameter: factoryONo)
    }
    
    func delete(member objectNumber: OcaONo) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.4"),
                                 parameter: objectNumber)
    }
    
    func getRecursive() async throws -> OcaList<OcaBlockMember> {
        try await sendCommandRrq(methodID: OcaMethodID("3.6"))
    }
    
    func add(signalPath path: OcaSignalPath) async throws -> OcaUint16 {
        try await sendCommandRrq(methodID: OcaMethodID("3.7"),
                                 parameter: path)
    }
    
    func delete(signalPath index: OcaUint16) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.8"),
                                 parameter: index)
    }
    
    func getRecursive() async throws -> OcaMap<OcaUint16, OcaSignalPath> {
        try await sendCommandRrq(methodID: OcaMethodID("3.10"))
    }
    
    func apply(paramSet identifier: OcaLibVolIdentifier) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.12"),
                                 parameter: identifier)
    }
    
    func get() async throws -> OcaLibVolData_ParamSet {
        try await sendCommandRrq(methodID: OcaMethodID("3.13"))
    }
    
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
    
    func find(objectsByRole searchName: OcaString,
              nameComparisonType: OcaStringComparisonType,
              searchClassID: OcaClassID,
              resultFlags: OcaObjectSearchResultFlags) async throws -> OcaList<OcaObjectSearchResult>{
        let params = FindObjectsByRoleParameters(searchName: searchName,
                                                 nameComparisonType: nameComparisonType,
                                                 searchClassID: searchClassID,
                                                 resultFlags: resultFlags)
        
        return try await sendCommandRrq(methodID: OcaMethodID("3.17"), parameter: params)
    }
    
    func findRecursive(objectsByRole searchName: OcaString,
                       nameComparisonType: OcaStringComparisonType,
                       searchClassID: OcaClassID,
                       resultFlags: OcaObjectSearchResultFlags) async throws -> OcaList<OcaObjectSearchResult> {
        let params = FindObjectsByRoleParameters(searchName: searchName,
                                                 nameComparisonType: nameComparisonType,
                                                 searchClassID: searchClassID,
                                                 resultFlags: resultFlags)
        
        return try await sendCommandRrq(methodID: OcaMethodID("3.18"), parameter: params)
    }
    
    // 3.19
    func find(objectsByPath searchPath: OcaString,
              resultFlags: OcaObjectSearchResultFlags,
              result: inout OcaList<OcaObjectSearchResult>) async throws {
        throw Ocp1Error.notImplemented
    }
    
    // 3.20
    func findRecursive(objectsByLabel searchName: OcaString,
                       nameComparisonType: OcaStringComparisonType,
                       searchClassID: OcaClassID,
                       resultFlags: OcaObjectSearchResultFlags,
                       result: inout OcaList<OcaObjectSearchResult>) async throws {
        throw Ocp1Error.notImplemented
    }
    
    public override var isContainer: Bool {
        true
    }
}

extension OcaBlock {
    @MainActor
    public func resolveMembers() async throws -> OcaList<OcaRoot> {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        return try await self._members.onCompletion(self) { members in
            members.compactMap { connectionDelegate.resolve(object: $0) }
        }
    }
        
    @MainActor
    public func resolveMembersRecursive(resolveMatrixMembers: Bool = false) async throws -> [OcaContainerObjectMember] {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let recursiveMembers: OcaList<OcaBlockMember> = try await getRecursive()
        var containerMembers: [OcaContainerObjectMember]
        
        containerMembers = recursiveMembers.compactMap { member in
            let memberObject = connectionDelegate.resolve(object: member.memberObjectIdentification)
            guard let memberObject else { return nil }
            return OcaContainerObjectMember(memberObject: memberObject,
                                            containerObjectNumber: member.containerObjectNumber)
        }
                
        if resolveMatrixMembers {
            for member in containerMembers {
                guard let member = member.memberObject as? OcaMatrix else {
                    continue
                }
                
                let matrixMembers = try await member.resolveMembers()
                
                for x in 0..<matrixMembers.nX {
                    for y in 0..<matrixMembers.nY {
                        guard let object = matrixMembers[x, y] else { continue }
                        containerMembers.append(OcaContainerObjectMember(memberObject: object,
                                                                         containerObjectNumber: member.objectNumber))
                    }
                }
            }
        }
        
        return containerMembers
    }
}

extension Array where Element: OcaRoot {
    public var hasContainerMembers: Bool {
        return self.allSatisfy { $0.isContainer }
    }
}
