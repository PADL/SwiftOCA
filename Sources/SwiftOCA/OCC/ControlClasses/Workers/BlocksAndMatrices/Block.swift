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

public struct OcaBlockMember: Codable, Sendable {
    public let memberObjectIdentification: OcaObjectIdentification
    public let containerObjectNumber: OcaONo

    public init(
        memberObjectIdentification: OcaObjectIdentification,
        containerObjectNumber: OcaONo
    ) {
        self.memberObjectIdentification = memberObjectIdentification
        self.containerObjectNumber = containerObjectNumber
    }
}

public struct OcaContainerObjectMember: Sendable {
    public let memberObject: OcaRoot
    public let containerObjectNumber: OcaONo

    public init(memberObject: OcaRoot, containerObjectNumber: OcaONo) {
        self.memberObject = memberObject
        self.containerObjectNumber = containerObjectNumber
    }
}

open class OcaBlock: OcaWorker {
    override open class var classID: OcaClassID { OcaClassID("1.1.3") }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var type: OcaProperty<OcaONo>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.5")
    )
    public var actionObjects: OcaListProperty<OcaObjectIdentification>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.9")
    )
    public var signalPaths: OcaMapProperty<OcaUint16, OcaSignalPath>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.11")
    )
    public var mostRecentParamSetIdentifier: OcaProperty<OcaLibVolIdentifier>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.15")
    )
    public var globalType: OcaProperty<OcaGlobalTypeIdentifier>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.16")
    )
    public var oNoMap: OcaMapProperty<OcaProtoONo, OcaONo>.PropertyValue

    // 3.2
    func constructActionObject(
        classID: OcaClassID,
        constructionParameters: [any Codable]
    ) async throws -> OcaONo {
        throw Ocp1Error.notImplemented
    }

    public func constructActionObject(factory factoryONo: OcaONo) async throws -> OcaONo {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.3"),
            parameters: factoryONo
        )
    }

    public func delete(actionObject objectNumber: OcaONo) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.4"),
            parameters: objectNumber
        )
    }

    public func getRecursive() async throws -> OcaList<OcaBlockMember> {
        try await sendCommandRrq(methodID: OcaMethodID("3.6"))
    }

    public func add(signalPath path: OcaSignalPath) async throws -> OcaUint16 {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.7"),
            parameters: path
        )
    }

    public func delete(signalPath index: OcaUint16) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.8"),
            parameters: index
        )
    }

    public func getRecursive() async throws -> OcaMap<OcaUint16, OcaSignalPath> {
        try await sendCommandRrq(methodID: OcaMethodID("3.10"))
    }

    public func apply(paramSet identifier: OcaLibVolIdentifier) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.12"),
            parameters: identifier
        )
    }

    public func get() async throws -> OcaLibVolData_ParamSet {
        try await sendCommandRrq(methodID: OcaMethodID("3.13"))
    }

    public func store(currentParamSet identifier: OcaLibVolIdentifier) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("3.14"),
            parameters: identifier
        )
    }

    public struct FindActionObjectsByRoleParameters: Ocp1ParametersReflectable {
        public let searchName: OcaString
        public let nameComparisonType: OcaStringComparisonType
        public let searchClassID: OcaClassID
        public let resultFlags: OcaObjectSearchResultFlags

        public init(
            searchName: OcaString,
            nameComparisonType: OcaStringComparisonType,
            searchClassID: OcaClassID,
            resultFlags: OcaObjectSearchResultFlags
        ) {
            self.searchName = searchName
            self.nameComparisonType = nameComparisonType
            self.searchClassID = searchClassID
            self.resultFlags = resultFlags
        }
    }

    public func find(
        actionObjectsByRole searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> OcaList<OcaObjectSearchResult> {
        let params = FindActionObjectsByRoleParameters(
            searchName: searchName,
            nameComparisonType: nameComparisonType,
            searchClassID: searchClassID,
            resultFlags: resultFlags
        )
        let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
        return try await sendCommandRrq(
            methodID: OcaMethodID("3.17"),
            parameters: params,
            userInfo: userInfo
        )
    }

    public func findRecursive(
        actionObjectsByRole searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> OcaList<OcaObjectSearchResult> {
        let params = FindActionObjectsByRoleParameters(
            searchName: searchName,
            nameComparisonType: nameComparisonType,
            searchClassID: searchClassID,
            resultFlags: resultFlags
        )
        let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
        return try await sendCommandRrq(
            methodID: OcaMethodID("3.18"),
            parameters: params,
            userInfo: userInfo
        )
    }

    public struct FindActionObjectsByPathParameters: Ocp1ParametersReflectable {
        public let searchPath: OcaNamePath
        public let resultFlags: OcaObjectSearchResultFlags

        public init(searchPath: OcaNamePath, resultFlags: OcaObjectSearchResultFlags) {
            self.searchPath = searchPath
            self.resultFlags = resultFlags
        }
    }

    public func findRecursive(
        actionObjectsByLabel searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> OcaList<OcaObjectSearchResult> {
        let params = FindActionObjectsByRoleParameters(
            searchName: searchName,
            nameComparisonType: nameComparisonType,
            searchClassID: searchClassID,
            resultFlags: resultFlags
        )
        let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
        return try await sendCommandRrq(
            methodID: OcaMethodID("3.19"),
            parameters: params,
            userInfo: userInfo
        )
    }

    public func find(
        actionObjectsByPath searchPath: OcaNamePath,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> OcaList<OcaObjectSearchResult> {
        let params = FindActionObjectsByPathParameters(
            searchPath: searchPath,
            resultFlags: resultFlags
        )
        let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
        return try await sendCommandRrq(
            methodID: OcaMethodID("3.20"),
            parameters: params,
            userInfo: userInfo
        )
    }

    override public var isContainer: Bool {
        true
    }

    override public var jsonObject: [String: Any] {
        get async {
            var jsonObject = await super.jsonObject
            jsonObject["3.2"] = try? await resolveActionObjects().asyncMap { await $0.jsonObject }
            return jsonObject
        }
    }
}

public extension OcaBlock {
    @OcaConnection
    func resolveActionObjects() async throws -> [OcaRoot] {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        return try await _actionObjects.onCompletion(self) { actionObjects in
            await actionObjects.asyncCompactMap { await connectionDelegate.resolve(object: $0) }
        }
    }

    @OcaConnection
    func resolveActionObjectsRecursive() async throws
        -> [OcaContainerObjectMember]
    {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let recursiveMembers: OcaList<OcaBlockMember> = try await getRecursive()
        var containerMembers: [OcaContainerObjectMember]

        containerMembers = recursiveMembers.compactMap { member in
            let memberObject = connectionDelegate.resolve(object: member.memberObjectIdentification)
            guard let memberObject else { return nil }
            return OcaContainerObjectMember(
                memberObject: memberObject,
                containerObjectNumber: member.containerObjectNumber
            )
        }

        return containerMembers
    }
}

public extension Array where Element: OcaRoot {
    var hasContainerMembers: Bool {
        allSatisfy(\.isContainer)
    }
}
