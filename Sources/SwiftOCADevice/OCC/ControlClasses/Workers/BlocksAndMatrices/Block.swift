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
  #if NonEmbeddedBuild
  var datasetObjects: [OcaDataset] {
    get async throws
  }
  var globalType: OcaGlobalTypeIdentifier? {
    get
  }
  #endif
}

@OcaDeviceMethods
open class OcaBlock<ActionObject: OcaRoot>: OcaWorker, OcaBlockContainer {
  override open class var classID: OcaClassID {
    OcaClassID("1.1.3")
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var type: OcaONo = OcaInvalidONo

  public private(set) var actionObjects = [ActionObject]()

  #if NonEmbeddedBuild
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
  #endif

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
      throw Ocp1Error.objectAlreadyContainedByBlock(object.objectNumber)
    }

    if let object = object as? OcaOwnable {
      guard object.owner == OcaInvalidONo else {
        throw Ocp1Error.objectAlreadyContainedByBlock(object.objectNumber)
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
    getMethodID: OcaMethodID("3.9"),
    ocp2GetName: "Members"
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

  /// this is deprecated (replaced with mostRecentParamDatasetONo) but we return
  /// zero to keep SwiftOCA clients happy
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.11"),
    ocp2GetName: "Identifier"
  )
  public var mostRecentParamSetIdentifier: OcaLibVolIdentifier = .init(
    library: OcaInvalidONo,
    id: 0
  )

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

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.22"),
    ocp2GetName: "ONo"
  )
  public var mostRecentParamDatasetONo: OcaONo = OcaInvalidONo

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

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.getActionObjectsRecursive)
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

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.getSignalPathsRecursive)
  func getSignalPathsRecursive(from controller: any OcaController) async throws
    -> OcaMap<OcaUint16, OcaSignalPath>
  {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.findActionObjectsByRole)
  func findActionObjectsByRole(
    searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID,
    resultFlags: OcaActionObjectSearchResultFlags,
    from controller: any OcaController
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

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.findActionObjectsByRoleRecursive)
  func findActionObjectsByRoleRecursive(
    searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID,
    resultFlags: OcaActionObjectSearchResultFlags,
    from controller: any OcaController
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

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.findActionObjectsByRolePath)
  public func findActionObjectsByRolePath(
    searchPath: OcaNamePath,
    resultFlags: OcaActionObjectSearchResultFlags,
    from controller: any OcaController
  ) async throws -> [OcaObjectSearchResult] {
    let selfRolePath = await rolePath
    return await filterRecursive(maxDepth: searchPath.count) { member, _ in
      await member.rolePath == selfRolePath + searchPath
    }.async.map { member in
      await member.makeSearchResult(with: resultFlags)
    }.collect()
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.findActionObjectsByLabelRecursive)
  func findActionObjectsByLabelRecursive(
    searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID,
    resultFlags: OcaActionObjectSearchResultFlags,
    from controller: any OcaController
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

  #if NonEmbeddedBuild
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

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.applyParamDataset)
  open func applyParamDataset(oNo: OcaONo, from controller: OcaController?) async throws {
    guard let provider = await deviceDelegate?.datasetStorageProvider else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    do {
      let dataset = try await provider.resolve(targetONo: objectNumber, datasetONo: oNo)
      try await dataset.applyParameters(to: self, controller: controller)
      mostRecentParamDatasetONo = dataset.objectNumber
    } catch {
      await deviceDelegate?.logger
        .warning("failed to apply parameter data set \(oNo.oNoString): \(error)")
      throw error
    }
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.storeCurrentParameterData, access: .write)
  open func storeCurrentParameterData(
    oNo: OcaONo,
    from controller: OcaController?
  ) async throws {
    guard let provider = await deviceDelegate?.datasetStorageProvider else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    do {
      let dataset = try await provider.resolve(targetONo: objectNumber, datasetONo: oNo)
      try await dataset.storeParameters(object: self, controller: controller)
      try? await notifySubscribers(datasetObjects: datasetObjects, changeType: .itemChanged)
    } catch {
      await deviceDelegate?.logger
        .warning("failed to store current parameter data into \(oNo.oNoString): \(error)")
      throw error
    }
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.fetchCurrentParameterData, access: .read)
  open func fetchCurrentParameterData(from controller: any OcaController) async throws -> OcaLongBlob {
    do {
      return try await serializeParameterDataset(compress: true)
    } catch {
      await deviceDelegate?.logger.warning("failed to fetch current parameter data: \(error)")
      throw error
    }
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.applyParameterData)
  open func applyParameterData(data: OcaLongBlob, from controller: OcaController?) async throws {
    try await deserializeParameterDataset(from: data)
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

  open func datasetObjectsRecursive(from controller: OcaController) async throws
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
    throw Ocp1Error.status(.notImplemented)
  }
  #endif

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.getActionObjects)
  func getActionObjects(from controller: any OcaController) -> [OcaObjectIdentification] {
    actionObjects.map(\.objectIdentification)
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.addSignalPath)
  func addSignalPath(path: OcaSignalPath, from controller: any OcaController) async throws -> OcaUint16 {
    try await add(signalPath: path)
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.deleteSignalPath)
  func deleteSignalPath(index: OcaUint16, from controller: any OcaController) async throws {
    try await delete(signalPathAt: index)
  }

  #if NonEmbeddedBuild
  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.constructDataset)
  func constructDataset(
    classID: OcaClassID,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob,
    from controller: any OcaController
  ) async throws -> OcaONo {
    try await constructDataset(
      classID: classID,
      name: name,
      type: type,
      maxSize: maxSize,
      initialContents: initialContents,
      controller: controller
    )
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.duplicateDataset)
  func duplicateDataset(
    oldONo: OcaONo,
    targetBlockONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    from controller: any OcaController
  ) async throws -> OcaONo {
    try await duplicateDataset(
      oldONo: oldONo,
      targetBlockONo: targetBlockONo,
      newName: newName,
      newMaxSize: newMaxSize,
      controller: controller
    )
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.getDatasetObjects)
  func getDatasetObjects(from controller: any OcaController) async throws -> [OcaObjectIdentification] {
    try await datasetObjects.map(\.objectIdentification)
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.getDatasetObjectsRecursive)
  func getDatasetObjectsRecursive(from controller: any OcaController) async throws
    -> [OcaBlockMember]
  {
    try await datasetObjectsRecursive(from: controller).map { dataset in
      OcaBlockMember(
        memberObjectIdentification: dataset.objectIdentification,
        containerObjectNumber: dataset.owner
      )
    }
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.findDatasets)
  func findDatasets(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType,
    from controller: any OcaController
  ) async throws -> [OcaDatasetSearchResult] {
    try await datasetSearchResults(findDatasets(
      name: name,
      nameComparisonType: nameComparisonType,
      type: type,
      typeComparisonType: typeComparisonType
    ))
  }

  @OcaDeviceMethod(SwiftOCA.OcaBlock.Methods.findDatasetsRecursive)
  func findDatasetsRecursive(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType,
    from controller: any OcaController
  ) async throws -> [OcaDatasetSearchResult] {
    try await datasetSearchResults(findDatasetsRecursive(
      name: name,
      nameComparisonType: nameComparisonType,
      type: type,
      typeComparisonType: typeComparisonType
    ))
  }

  private func datasetSearchResults(_ datasets: [OcaDataset]) -> [OcaDatasetSearchResult] {
    datasets.map { dataset in
      let blockMember = OcaBlockMember(
        memberObjectIdentification: dataset.objectIdentification,
        containerObjectNumber: objectNumber
      )
      return OcaDatasetSearchResult(object: blockMember, name: dataset.name, type: dataset.type)
    }
  }
  #endif

  override public var isContainer: Bool {
    true
  }

  #if NonEmbeddedBuild
  override open func serialize(
    flags: OcaRoot.SerializationFlags = [],
    filter: OcaRoot.SerializationFilterFunction? = nil
  ) throws -> [String: any Sendable] {
    var jsonObject = try super.serialize(flags: flags, filter: filter)

    jsonObject["3.2"] = try actionObjects.compactMap { actionObject in
      try actionObject.serialize(flags: flags, filter: filter)
    }

    return jsonObject
  }

  override open func deserialize(
    jsonObject: [String: Sendable],
    flags: DeserializationFlags = [],
    filter: DeserializationFilterFunction? = nil
  ) async throws {
    try await super.deserialize(jsonObject: jsonObject, flags: flags, filter: filter)

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
        if flags.contains(.ignoreDecodingErrors) {
          continue
        } else {
          throw Ocp1Error.status(.badFormat)
        }
      }

      guard let actionObject = actionObjects.first(where: { $0.objectNumber == objectNumber })
      else {
        if flags.contains(.ignoreUnknownObjectNumbers) {
          continue
        } else {
          throw Ocp1Error.objectNotPresent(objectNumber)
        }
      }

      try await actionObject.deserialize(
        jsonObject: actionJsonObject,
        flags: flags,
        filter: filter
      )
    }
  }
  #endif
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
      await OcaGetPathParameters(rolePath: rolePath, oNoPath: objectNumberPath)
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
