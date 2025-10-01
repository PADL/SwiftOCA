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
@_spi(SwiftOCAPrivate)
import SwiftOCA

@OcaDevice
public protocol OcaBlockContainer: OcaRoot {
  associatedtype ActionObject: OcaRoot

  var actionObjects: [ActionObject] { get }
  var datasetObjects: [OcaDataset] { get async throws }
}

open class OcaBlock<ActionObject: OcaRoot>: OcaWorker, OcaBlockContainer {
  override open class var classID: OcaClassID { OcaClassID("1.1.3") }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var type: OcaONo = OcaInvalidONo

  public private(set) var actionObjects = [ActionObject]()
  public var datasetObjects: [OcaDataset] {
    get async throws {
      guard let provider = await deviceDelegate?.datasetStorageProvider else {
        throw Ocp1Error.noDatasetStorageProvider
      }
      return try await provider.getDatasetObjects(targetONo: objectNumber)
    }
  }

  var datasetFilter: OcaRoot.SerializationFilterFunction?

  public func set(datasetFilter: OcaRoot.SerializationFilterFunction?) {
    self.datasetFilter = datasetFilter
  }

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
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.22")
  )
  public var mostRecentParamDatasetONo: OcaONo = OcaInvalidONo

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

  public typealias BlockApplyFunction<U> = (
    _ member: OcaRoot,
    _ container: any OcaBlockContainer
  ) async throws -> U

  private func applyRecursive(
    rootObject: any OcaBlockContainer,
    maxDepth: Int,
    depth: Int,
    _ block: BlockApplyFunction<()>
  ) async rethrows {
    for member in rootObject.actionObjects {
      try await block(member, rootObject)
      if let member = member as? any OcaBlockContainer, maxDepth == -1 || depth < maxDepth {
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

  public func filterRecursive(
    maxDepth: Int = -1,
    _ isIncluded: @escaping (OcaRoot, any OcaBlockContainer) async throws -> Bool
  ) async rethrows -> [OcaRoot] {
    var actionObjects = [OcaRoot]()

    try await applyRecursive(maxDepth: maxDepth) { member, container in
      if try await isIncluded(member, container) {
        actionObjects.append(member)
      }
    }

    return actionObjects
  }

  public func mapRecursive<U: Sendable>(
    maxDepth: Int = -1,
    _ transform: BlockApplyFunction<U>
  ) async rethrows -> [U] {
    var actionObjects = [U]()

    try await applyRecursive(maxDepth: maxDepth) { member, container in
      try await actionObjects.append(transform(member, container))
    }

    return actionObjects
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

  public func find(
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
        agent.compare(
          searchName: searchName,
          keyPath: \OcaAgent.label,
          nameComparisonType: nameComparisonType,
          searchClassID: searchClassID
        )
      } else if let worker = member as? OcaWorker {
        worker.compare(
          searchName: searchName,
          keyPath: \OcaWorker.label,
          nameComparisonType: nameComparisonType,
          searchClassID: searchClassID
        )
      } else {
        false
      }
    }.async.map { member in
      await member.makeSearchResult(with: resultFlags)
    }.collect()
  }

  private typealias DatasetApplyFunction<U> = (
    _ member: OcaDataset,
    _ container: any OcaBlockContainer
  ) async throws -> U

  private func applyRecursive(
    rootObject: any OcaBlockContainer,
    maxDepth: Int,
    depth: Int,
    _ block: DatasetApplyFunction<()>
  ) async throws {
    for member in try await rootObject.datasetObjects {
      try await block(member, rootObject)
      if let member = member as? (any OcaBlockContainer), maxDepth == -1 || depth < maxDepth {
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
    _ block: DatasetApplyFunction<()>
  ) async throws {
    try await applyRecursive(
      rootObject: self,
      maxDepth: maxDepth,
      depth: 1,
      block
    )
  }

  private func filterRecursive(
    maxDepth: Int = -1,
    _ isIncluded: @escaping (OcaDataset, any OcaBlockContainer) async throws -> Bool
  ) async throws -> [OcaRoot] {
    var actionObjects = [OcaRoot]()

    try await applyRecursive(maxDepth: maxDepth) { member, container in
      if try await isIncluded(member, container) {
        actionObjects.append(member)
      }
    }

    return actionObjects
  }

  private func mapRecursive<U: Sendable>(
    maxDepth: Int = -1,
    _ transform: DatasetApplyFunction<U>
  ) async throws -> [U] {
    var actionObjects = [U]()

    try await applyRecursive(maxDepth: maxDepth) { member, container in
      try await actionObjects.append(transform(member, container))
    }

    return actionObjects
  }

  private func notifySubscribers(
    datasetObjects: [OcaDataset],
    changeType: OcaPropertyChangeType
  ) async throws {
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = OcaPropertyChangedEventData<[OcaDataset]>(
      propertyID: OcaPropertyID("3.7"),
      propertyValue: datasetObjects,
      changeType: changeType
    )

    try await deviceDelegate?.notifySubscribers(
      event,
      parameters: parameters
    )
  }

  open func delete(datasetObject object: OcaDataset) async throws {
    if object.objectNumber == OcaInvalidONo {
      throw Ocp1Error.status(.badONo)
    }

    guard let provider = await deviceDelegate?.datasetStorageProvider else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    try await provider.delete(targetONo: objectNumber, datasetONo: object.objectNumber)
    try? await notifySubscribers(datasetObjects: datasetObjects, changeType: .itemDeleted)
  }

  open func resolve(paramDataset oNo: OcaONo) async throws -> OcaDataset {
    guard let datasetObject = try await datasetObjects.first(where: { $0.objectNumber == oNo })
    else {
      throw Ocp1Error.objectNotPresent(oNo)
    }
    return datasetObject
  }

  open func apply(paramDataset: OcaONo, controller: OcaController?) async throws {
    guard let provider = await deviceDelegate?.datasetStorageProvider else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    do {
      let dataset = try await provider.resolve(targetONo: objectNumber, datasetONo: paramDataset)
      try await dataset.applyParameters(to: self, controller: controller)
      mostRecentParamDatasetONo = dataset.objectNumber
    } catch {
      await deviceDelegate?.logger
        .warning("failed to apply parameter data set \(paramDataset.oNoString): \(error)")
      throw error
    }
  }

  open func store(
    currentParameterData paramDataset: OcaONo,
    controller: OcaController?
  ) async throws {
    guard let provider = await deviceDelegate?.datasetStorageProvider else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    do {
      let dataset = try await provider.resolve(targetONo: objectNumber, datasetONo: paramDataset)
      try await dataset.storeParameters(object: self, controller: controller)
      try? await notifySubscribers(datasetObjects: datasetObjects, changeType: .itemChanged)
    } catch {
      await deviceDelegate?.logger
        .warning("failed to store current parameter data into \(paramDataset.oNoString): \(error)")
      throw error
    }
  }

  open func fetchCurrentParameterData() async throws -> OcaLongBlob {
    do {
      return try await serializeParameterDataset(compress: true)
    } catch {
      await deviceDelegate?.logger.warning("failed to fetch current parameter data: \(error)")
      throw error
    }
  }

  open func apply(parameterData: OcaLongBlob, controller: OcaController?) async throws {
    try await deserializeParameterDataset(from: parameterData)
  }

  open func constructDataset(
    classID: OcaClassID,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob,
    controller: OcaController?,
    desiredDatasetONo: OcaONo? = nil
  ) async throws -> OcaONo {
    guard let provider = await deviceDelegate?.datasetStorageProvider else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    do {
      let oNo = try await provider.construct(
        classID: classID,
        targetONo: objectNumber,
        datasetONo: desiredDatasetONo,
        name: name,
        type: type,
        maxSize: maxSize,
        initialContents: initialContents,
        controller: controller
      )
      try? await notifySubscribers(datasetObjects: datasetObjects, changeType: .itemAdded)
      return oNo
    } catch {
      await deviceDelegate?.logger
        .warning("failed to construct dataset object \(name) type \(type): \(error)")
      throw error
    }
  }

  open func duplicateDataset(
    oldONo: OcaONo,
    targetBlockONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    controller: OcaController?,
    desiredDatasetONo: OcaONo? = nil
  ) async throws -> OcaONo {
    guard let provider = await deviceDelegate?.datasetStorageProvider else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    // validate the target block actually exists
    guard let targetBlock = await deviceDelegate?.objects[targetBlockONo] as? Self else {
      throw Ocp1Error.status(.badONo)
    }

    do {
      let oNo = try await provider.duplicate(
        oldDatasetONo: oldONo,
        oldTargetONo: objectNumber,
        newDatasetONo: desiredDatasetONo,
        newTargetONo: targetBlockONo,
        newName: newName,
        newMaxSize: newMaxSize,
        controller: controller
      )
      try? await targetBlock.notifySubscribers(
        datasetObjects: targetBlock.datasetObjects,
        changeType: .itemAdded
      )
      return oNo
    } catch {
      await deviceDelegate?.logger
        .warning(
          "failed to duplicate dataset object \(oldONo.oNoString) to \(targetBlockONo.oNoString): \(error)"
        )
      throw error
    }
  }

  open func getDatasetObjectsRecursive(from controller: OcaController) async throws
    -> [OcaDataset]
  {
    try await mapRecursive(maxDepth: -1) { member, _ in
      member
    }
  }

  open func findDatasets(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType
  ) async throws -> [OcaDataset] {
    guard typeComparisonType == .exact else {
      throw Ocp1Error.status(.parameterError)
    }

    switch type {
    case OcaParamDatasetMimeType:
      guard let provider = await deviceDelegate?.datasetStorageProvider else {
        throw Ocp1Error.noDatasetStorageProvider
      }
      return try await provider.find(
        targetONo: objectNumber,
        name: name,
        nameComparisonType: nameComparisonType
      )
    default:
      throw Ocp1Error.unknownDatasetMimeType
    }
  }

  open func findDatasetsRecursive(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType
  ) async throws -> [OcaDataset] {
    throw Ocp1Error.notImplemented
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
    case OcaMethodID("3.23"):
      let params: OcaONo = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await apply(paramDataset: params, controller: controller)
    case OcaMethodID("3.24"):
      let params: OcaONo = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await store(currentParameterData: params, controller: controller)
    case OcaMethodID("3.25"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let paramData = try await fetchCurrentParameterData()
      return try encodeResponse(paramData)
    case OcaMethodID("3.26"):
      let paramData: OcaLongBlob = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await apply(parameterData: paramData, controller: controller)
    case OcaMethodID("3.27"):
      let params: SwiftOCA.OcaBlock.ConstructDataSetParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      let oNo = try await constructDataset(
        classID: params.classID,
        name: params.name,
        type: params.type,
        maxSize: params.maxSize,
        initialContents: params.initialContents,
        controller: controller
      )
      return try encodeResponse(oNo)
    case OcaMethodID("3.28"):
      let params: SwiftOCA.OcaBlock.DuplicateDataSetParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      let oNo = try await duplicateDataset(
        oldONo: params.oldONo,
        targetBlockONo: params.targetBlockONo,
        newName: params.newName,
        newMaxSize: params.newMaxSize,
        controller: controller
      )
      return try encodeResponse(oNo)
    case OcaMethodID("3.29"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let datasetObjecst = try await datasetObjects.map(\.objectIdentification)
      return try encodeResponse(datasetObjecst)
    case OcaMethodID("3.30"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let datasetObjects: [OcaBlockMember] =
        try await getDatasetObjectsRecursive(from: controller).map { dataset in
          OcaBlockMember(
            memberObjectIdentification: dataset.objectIdentification,
            containerObjectNumber: dataset.owner
          )
        }
      return try encodeResponse(datasetObjects)
    case OcaMethodID("3.31"):
      let params: SwiftOCA.OcaBlock.FindDatasetsParameters = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      let datasets: [OcaDataset] = if command.methodID == "3.31" {
        try await findDatasets(
          name: params.name,
          nameComparisonType: params.nameComparisonType,
          type: params.type,
          typeComparisonType: params.typeComparisonType
        )
      } else {
        try await findDatasetsRecursive(
          name: params.name,
          nameComparisonType: params.nameComparisonType,
          type: params.type,
          typeComparisonType: params.typeComparisonType
        )
      }
      let searchResults = datasets.map { dataset in
        let blockMember = OcaBlockMember(
          memberObjectIdentification: dataset.objectIdentification,
          containerObjectNumber: self.objectNumber
        )
        return OcaDatasetSearchResult(object: blockMember, name: dataset.name, type: dataset.type)
      }
      return try encodeResponse(searchResults)
    // 3.32 FindDatasetsRecursive
    default:
      return try await super.handleCommand(command, from: controller)
    }
    return Ocp1Response()
  }

  override public var isContainer: Bool {
    true
  }

  override public func serialize(
    flags: OcaRoot.SerializationFlags = [],
    isIncluded: OcaRoot.SerializationFilterFunction? = nil
  ) throws -> [String: Any] {
    var jsonObject = try super.serialize(flags: flags, isIncluded: isIncluded)

    jsonObject["3.2"] = try actionObjects.compactMap { actionObject in
      try actionObject.serialize(flags: flags, isIncluded: isIncluded)
    }

    return jsonObject
  }

  override public func deserialize(
    jsonObject: [String: Sendable],
    flags: DeserializationFlags = []
  ) async throws {
    try await super.deserialize(jsonObject: jsonObject, flags: flags)

    guard let actionJsonObjects = jsonObject["3.2"] as? [[String: Sendable]] else {
      return
    }

    for actionJsonObject in actionJsonObjects {
      guard !actionJsonObject.isEmpty else {
        continue
      }

      let objectNumber: OcaONo

      do {
        objectNumber = try _getObjectNumberFromJsonObject(jsonObject: actionJsonObject)
      } catch {
        if flags.contains(.ignoreDecodingErrors) { continue }
        else { throw Ocp1Error.status(.badFormat) }
      }

      guard let actionObject = actionObjects.first(where: { $0.objectNumber == objectNumber })
      else {
        if flags.contains(.ignoreUnknownObjectNumbers) { continue }
        else { throw Ocp1Error.objectNotPresent(objectNumber) }
      }

      try await actionObject.deserialize(jsonObject: actionJsonObject, flags: flags)
    }
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
      await path.insert(contentsOf: makePath(rootObject: container, keyPath: keyPath), at: 0)
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
      await OcaGetPathParameters(namePath: rolePath, oNoPath: objectNumberPath)
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

    return nameComparisonType.compare(value, searchName)
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
