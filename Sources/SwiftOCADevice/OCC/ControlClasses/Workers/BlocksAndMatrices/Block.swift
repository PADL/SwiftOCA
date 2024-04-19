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

import AsyncExtensions
import SwiftOCA

@OcaDevice
private protocol OcaBlockContainer: OcaRoot {
    var members: [OcaRoot] { get }
}

open class OcaBlock<ActionObject: OcaRoot>: OcaWorker, OcaBlockContainer {
    override open class var classID: OcaClassID { OcaClassID("1.1.3") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var type: OcaONo = OcaInvalidONo

    public private(set) var actionObjects = [ActionObject]()

    fileprivate var members: [OcaRoot] { actionObjects }

    private func notifySubscribers(
        actionObjects: [ActionObject],
        changeType: OcaPropertyChangeType
    ) async throws {
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        let parameters = OcaPropertyChangedEventData<[ActionObject]>(
            propertyID: OcaPropertyID("3.2"),
            propertyValue: actionObjects,
            changeType: changeType
        )

        try await deviceDelegate?.notifySubscribers(
            event,
            parameters: parameters
        )
    }

    open func add(actionObject object: ActionObject) async throws {
        guard object.objectNumber != OcaInvalidONo else {
            throw Ocp1Error.status(.badONo)
        }

        guard object != self else {
            throw Ocp1Error.status(.parameterError)
        }

        guard !actionObjects.contains(object) else {
            throw Ocp1Error.objectAlreadyContainedByBlock
        }

        if let object = object as? OcaOwnable {
            guard object.owner == OcaInvalidONo else {
                throw Ocp1Error.objectAlreadyContainedByBlock
            }
            object.owner = objectNumber
        }

        if object.deviceDelegate == nil {
            object.deviceDelegate = deviceDelegate
        }

        actionObjects.append(object)
        try? await notifySubscribers(actionObjects: actionObjects, changeType: .itemAdded)
    }

    open func delete(actionObject object: ActionObject) async throws {
        if object.objectNumber == OcaInvalidONo {
            throw Ocp1Error.status(.badONo)
        }

        guard let index = actionObjects.firstIndex(of: object) else {
            throw Ocp1Error.objectNotPresent(object.objectNumber)
        }
        if let object = object as? OcaOwnable {
            if object.owner != objectNumber {
                throw Ocp1Error.objectNotPresent(object.objectNumber)
            }
            object.owner = OcaInvalidONo
        }

        actionObjects.remove(at: index)
        try? await notifySubscribers(actionObjects: actionObjects, changeType: .itemDeleted)
    }

    open func resolve(_ objectNumbers: OcaList<OcaONo>) throws -> [ActionObject] {
        try objectNumbers.map { oNo in
            guard let actionObject = actionObjects.first(where: { $0.objectNumber == oNo }) else {
                throw Ocp1Error.objectNotPresent(oNo)
            }
            return actionObject
        }
    }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.9")
    )
    public var signalPaths = OcaMap<OcaUint16, OcaSignalPath>()

    public func add(signalPath path: OcaSignalPath) async throws -> OcaUint16 {
        let index: OcaUint16 = 1 + (signalPaths.keys.max() ?? 0)
        signalPaths[index] = path
        return index
    }

    public func delete(signalPathAt index: OcaUint16) async throws {
        if !signalPaths.keys.contains(index) {
            throw Ocp1Error.status(.parameterOutOfRange)
        }
        signalPaths.removeValue(forKey: index)
    }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.11")
    )
    public var mostRecentParamSetIdentifier: OcaLibVolIdentifier?

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.15")
    )
    public var globalType: OcaGlobalTypeIdentifier?

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.16")
    )
    public var oNoMap = OcaMap<OcaProtoONo, OcaONo>()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.8"),
        getMethodID: OcaMethodID("3.21")
    )
    public var configurability = OcaBlockConfigurability()

    private typealias BlockApplyFunction<U> = (
        _ member: OcaRoot,
        _ container: OcaBlockContainer
    ) async throws -> U

    private func applyRecursive(
        rootObject: OcaBlockContainer,
        maxDepth: Int,
        depth: Int,
        _ block: BlockApplyFunction<()>
    ) async rethrows {
        for member in rootObject.members {
            try await block(member, rootObject)
            if let member = member as? OcaBlockContainer, maxDepth == -1 || depth < maxDepth {
                try await applyRecursive(
                    rootObject: member,
                    maxDepth: maxDepth,
                    depth: depth + 1,
                    block
                )
            }
        }
    }

    private func applyRecursive(
        maxDepth: Int = -1,
        _ block: BlockApplyFunction<()>
    ) async rethrows {
        try await applyRecursive(
            rootObject: self,
            maxDepth: maxDepth,
            depth: 1,
            block
        )
    }

    private func filterRecursive(
        maxDepth: Int = -1,
        _ isIncluded: @escaping (OcaRoot, OcaBlockContainer) async throws -> Bool
    ) async rethrows -> [OcaRoot] {
        var members = [OcaRoot]()

        try await applyRecursive(maxDepth: maxDepth) { member, container in
            if try await isIncluded(member, container) {
                members.append(member)
            }
        }

        return members
    }

    private func mapRecursive<U: Sendable>(
        maxDepth: Int = -1,
        _ transform: BlockApplyFunction<U>
    ) async rethrows -> [U] {
        var members = [U]()

        try await applyRecursive(maxDepth: maxDepth) { member, container in
            try await members.append(transform(member, container))
        }

        return members
    }

    func getActionObjectsRecursive(from controller: any OcaController) async throws
        -> OcaList<OcaBlockMember>
    {
        await mapRecursive(maxDepth: -1) { member, container in
            OcaBlockMember(
                memberObjectIdentification: member.objectIdentification,
                containerObjectNumber: container.objectNumber
            )
        }
    }

    func getSignalPathsRecursive(from controller: any OcaController) async throws
        -> OcaMap<OcaUint16, OcaSignalPath>
    {
        throw Ocp1Error.status(.notImplemented)
    }

    func find(
        actionObjectsByRole searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaActionObjectSearchResultFlags
    ) async throws -> [OcaObjectSearchResult] {
        await actionObjects.filter { member in
            member.compare(
                searchName: searchName,
                keyPath: \.role,
                nameComparisonType: nameComparisonType,
                searchClassID: searchClassID
            )
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.collect()
    }

    func findRecursive(
        actionObjectsByRole searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaActionObjectSearchResultFlags
    ) async throws -> [OcaObjectSearchResult] {
        await filterRecursive { member, _ in
            member.compare(
                searchName: searchName,
                keyPath: \.role,
                nameComparisonType: nameComparisonType,
                searchClassID: searchClassID
            )
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.collect()
    }

    func find(
        actionObjectsByRolePath searchPath: OcaNamePath,
        resultFlags: OcaActionObjectSearchResultFlags
    ) async throws -> [OcaObjectSearchResult] {
        let selfRolePath = await rolePath
        return await filterRecursive(maxDepth: searchPath.count) { member, _ in
            await member.rolePath == selfRolePath + searchPath
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.collect()
    }

    func findRecursive(
        actionObjectsByLabel searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaActionObjectSearchResultFlags
    ) async throws -> [OcaObjectSearchResult] {
        await filterRecursive { member, _ in
            if let agent = member as? OcaAgent {
                return agent.compare(
                    searchName: searchName,
                    keyPath: \OcaAgent.label,
                    nameComparisonType: nameComparisonType,
                    searchClassID: searchClassID
                )
            } else if let worker = member as? OcaWorker {
                return worker.compare(
                    searchName: searchName,
                    keyPath: \OcaWorker.label,
                    nameComparisonType: nameComparisonType,
                    searchClassID: searchClassID
                )
            } else {
                return false
            }
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.collect()
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        // 3.2 ConstructActionObject
        // 3.3 ConstructBlockUsingFactory
        // 3.4 DeleteMember
        case OcaMethodID("3.5"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            let actionObjects = actionObjects.map(\.objectIdentification)
            return try encodeResponse(actionObjects)
        case OcaMethodID("3.6"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            let actionObjects: [OcaBlockMember] =
                try await getActionObjectsRecursive(from: controller)
            return try encodeResponse(actionObjects)
        case OcaMethodID("3.7"):
            try decodeNullCommand(command)
            try await ensureWritable(by: controller, command: command)
            let path: OcaSignalPath = try decodeCommand(command)
            let index = try await add(signalPath: path)
            return try encodeResponse(index)
        case OcaMethodID("3.8"):
            try decodeNullCommand(command)
            try await ensureWritable(by: controller, command: command)
            let index: OcaUint16 = try decodeCommand(command)
            try await delete(signalPathAt: index)
        case OcaMethodID("3.10"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            let signalPaths: [OcaUint16: OcaSignalPath] =
                try await getSignalPathsRecursive(from: controller)
            return try encodeResponse(signalPaths)
        // 3.15 GetGlobalType
        // 3.16 GetONoMap
        case OcaMethodID("3.17"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByRoleParameters = try decodeCommand(command)
            try await ensureReadable(by: controller, command: command)
            let searchResult = try await find(
                actionObjectsByRole: params.searchName,
                nameComparisonType: params.nameComparisonType,
                searchClassID: params.searchClassID,
                resultFlags: params.resultFlags
            )
            return try encodeResponse(searchResult)
        case OcaMethodID("3.18"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByRoleParameters = try decodeCommand(command)
            try await ensureReadable(by: controller, command: command)
            let searchResult = try await findRecursive(
                actionObjectsByRole: params.searchName,
                nameComparisonType: params.nameComparisonType,
                searchClassID: params.searchClassID,
                resultFlags: params.resultFlags
            )
            return try encodeResponse(searchResult)
        case OcaMethodID("3.19"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByRoleParameters = try decodeCommand(command)
            try await ensureReadable(by: controller, command: command)
            let searchResult = try await findRecursive(
                actionObjectsByLabel: params.searchName,
                nameComparisonType: params.nameComparisonType,
                searchClassID: params.searchClassID,
                resultFlags: params.resultFlags
            )
            return try encodeResponse(searchResult)
        case OcaMethodID("3.20"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByPathParameters = try decodeCommand(command)
            try await ensureReadable(by: controller, command: command)
            let searchResult = try await find(
                actionObjectsByRolePath: params.searchPath,
                resultFlags: params.resultFlags
            )
            return try encodeResponse(searchResult)

        // 3.22 GetMostRecentParamDatasetONo
        // 3.23 ApplyParamDataset
        // 3.24 StoreCurrentParameterData
        // 3.25 FetchCurrentParameterData
        // 3.26 ApplyParameterData
        // 3.27 ConstructDataset
        // 3.28 DuplicateDataset
        // 3.29 GetDatasetObjects
        // 3.30 GetDatasetObjectsRecursive
        // 3.31 FindDatasets
        // 3.32 FindDatasetsRecursive
        default:
            return try await super.handleCommand(command, from: controller)
        }
        return Ocp1Response()
    }

    override public var isContainer: Bool {
        true
    }

    override public var jsonObject: [String: Any] {
        var jsonObject = super.jsonObject
        jsonObject["3.2"] = actionObjects.map(\.jsonObject)
        return jsonObject
    }
}

public extension OcaRoot {
    private func makePath<T: OcaRoot, U>(
        rootObject: T,
        keyPath: KeyPath<T, U>
    ) async -> [U] {
        guard rootObject.objectNumber != OcaRootBlockONo else { return [] }
        var path = [rootObject[keyPath: keyPath]]

        if let object = rootObject as? OcaOwnable,
           object.owner != OcaInvalidONo,
           let container = await deviceDelegate?.objects[object.owner] as? T
        {
            path.insert(contentsOf: await makePath(rootObject: container, keyPath: keyPath), at: 0)
        }

        return path
    }

    var objectNumberPath: OcaONoPath {
        get async {
            await makePath(rootObject: self, keyPath: \.objectNumber)
        }
    }

    var objectNumberPathString: String {
        get async {
            await "/" + objectNumberPath.map(\.description).joined(separator: "/")
        }
    }

    var rolePath: OcaNamePath {
        get async {
            await makePath(rootObject: self, keyPath: \.role)
        }
    }

    var rolePathString: String {
        get async {
            await "/" + rolePath.joined(separator: "/")
        }
    }

    var path: OcaGetPathParameters {
        get async {
            OcaGetPathParameters(namePath: await rolePath, oNoPath: await objectNumberPath)
        }
    }
}

private extension OcaRoot {
    func compare<T: OcaRoot>(
        searchName: OcaString,
        keyPath: KeyPath<T, String>,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID
    ) -> Bool {
        guard objectIdentification.classIdentification.classID.isSubclass(of: searchClassID),
              let object = self as? T
        else {
            return false
        }

        let value = object[keyPath: keyPath]

        switch nameComparisonType {
        case .exact:
            return value == searchName
        case .substring:
            return value.hasPrefix(searchName)
        case .contains:
            return value.contains(searchName)
        case .exactCaseInsensitive:
            return value.lowercased() == searchName.lowercased()
        case .substringCaseInsensitive:
            return value.lowercased().hasPrefix(searchName.lowercased())
        case .containsCaseInsensitive:
            return value.lowercased().contains(searchName.lowercased())
        }
    }

    func makeSearchResult(with resultFlags: OcaActionObjectSearchResultFlags) async
        -> OcaObjectSearchResult
    {
        var oNo: OcaONo?
        var classIdentification: OcaClassIdentification?
        var containerPath: OcaONoPath?
        var role: OcaString?
        var label: OcaString?

        if resultFlags.contains(.oNo) {
            oNo = objectNumber
        }
        if resultFlags.contains(.classIdentification) {
            classIdentification = objectIdentification.classIdentification
        }
        if resultFlags.contains(.containerPath) {
            containerPath = await objectNumberPath.dropLast()
        }
        if resultFlags.contains(.role) {
            role = self.role
        }
        if resultFlags.contains(.label), let worker = self as? OcaLabelRepresentable {
            label = worker.label
        }

        return OcaObjectSearchResult(
            oNo: oNo,
            classIdentification: classIdentification,
            containerPath: containerPath,
            role: role,
            label: label
        )
    }
}
