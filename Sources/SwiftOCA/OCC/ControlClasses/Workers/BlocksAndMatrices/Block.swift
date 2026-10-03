//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

public struct OcaBlockMember: Codable, Sendable, Hashable {
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

public struct OcaBlockConfigurability: OptionSet, Codable, Sendable {
  public static let actionObjects = OcaBlockConfigurability(rawValue: 1 << 0)
  public static let signalPaths = OcaBlockConfigurability(rawValue: 1 << 1)
  public static let datasetObjects = OcaBlockConfigurability(rawValue: 1 << 2)

  public let rawValue: OcaBitSet16

  public init(rawValue: OcaBitSet16) {
    self.rawValue = rawValue
  }
}

public struct OcaConstructionParameter: Codable, Sendable {
  public let id: OcaPropertyID
  public let value: OcaBlob

  public init(id: OcaPropertyID, value: OcaBlob) {
    self.id = id
    self.value = value
  }
}

open class OcaBlock: OcaWorker, @unchecked
Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.3") }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var type: OcaProperty<OcaONo>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.5"),
    ocp2GetName: "Objects"
  )
  public var actionObjects: OcaListProperty<OcaObjectIdentification>.PropertyValue

  // the property's getter, as the device declares it
  public static let getActionObjects = OcaMethodDescription<Void, [OcaObjectIdentification]>(
    "3.5",
    name: "GetActionObjects",
    resultNames: ["Objects"]
  )

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.9"),
    ocp2GetName: "Members"
  )
  public var signalPaths: OcaMapProperty<OcaUint16, OcaSignalPath>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.11"),
    ocp2GetName: "Identifier"
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

  @OcaProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.29"),
    ocp2GetName: "Objects"
  )
  public var datasetObjects: OcaProperty<[OcaObjectIdentification]>.PropertyValue

  public static let getDatasetObjects = OcaMethodDescription<Void, [OcaObjectIdentification]>(
    "3.29",
    name: "GetDatasetObjects",
    resultNames: ["Objects"]
  )

  @OcaProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.21")
  )
  public var configurability: OcaProperty<OcaBlockConfigurability>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.22"),
    ocp2GetName: "ONo"
  )
  public var mostRecentParamDatasetONo: OcaProperty<OcaONo>.PropertyValue

  public struct ConstructActionObjectParameters: OcaParametersReflectable {
    public let classID: OcaClassID
    public let constructionParameters: [OcaConstructionParameter]

    public init(classID: OcaClassID, constructionParameters: [OcaConstructionParameter]) {
      self.classID = classID
      self.constructionParameters = constructionParameters
    }
  }

  public static let constructActionObject =
    OcaMethodDescription<ConstructActionObjectParameters, OcaONo>(
      "3.2",
      name: "ConstructActionObject",
      resultNames: ["ObjectNumber"]
    )

  public func constructActionObject(
    classID: OcaClassID,
    constructionParameters: [OcaConstructionParameter]
  ) async throws -> OcaONo {
    try await invoke(
      Self.constructActionObject,
      .init(classID: classID, constructionParameters: constructionParameters)
    )
  }

  public static let constructBlockUsingFactory = OcaMethodDescription<OcaONo, OcaONo>(
    "3.3",
    name: "ConstructBlockUsingFactory",
    parameterNames: ["FactoryONo"],
    resultNames: ["ObjectNumber"]
  )

  public func constructActionObject(factory factoryONo: OcaONo) async throws -> OcaONo {
    try await invoke(Self.constructBlockUsingFactory, factoryONo)
  }

  public static let deleteMember = OcaMethodDescription<OcaONo, Void>(
    "3.4",
    name: "DeleteMember",
    parameterNames: ["ObjectNumber"]
  )

  public func delete(actionObject objectNumber: OcaONo) async throws {
    try await invoke(Self.deleteMember, objectNumber)
  }

  public static let getActionObjectsRecursive = OcaMethodDescription<Void, OcaList<OcaBlockMember>>(
    "3.6",
    name: "GetActionObjectsRecursive",
    resultNames: ["Objects"]
  )

  public func getActionObjectsRecursive() async throws -> OcaList<OcaBlockMember> {
    try await invoke(Self.getActionObjectsRecursive)
  }

  private func _getActionObjectsRecursiveFallback(
    _ blockMembers: inout Set<OcaBlockMember>
  ) async throws {
    let actionObjects = try await $actionObjects._getValue(
      self,
      flags: [.returnCachedValue, .cacheValue]
    )

    for actionObject in actionObjects {
      blockMembers
        .insert(OcaBlockMember(
          memberObjectIdentification: actionObject,
          containerObjectNumber: objectNumber
        ))
      if actionObject.classIdentification.isSubclass(of: OcaBlock.classIdentification),
         let actionObject: OcaBlock = try await connectionDelegate?
         .resolve(object: actionObject)
      {
        try await actionObject._getActionObjectsRecursiveFallback(&blockMembers)
      }
    }
  }

  /// this is a controller-side implementation of `getActionObjectsRecursive()` for devices that
  /// do not
  /// implement  `GetActionObjectsRecursive()`
  /// note that whilst we cache values here, we don't return cached values nor do we add any event
  /// subscriptions
  public func getActionObjectsRecursiveFallback() async throws -> OcaList<OcaBlockMember> {
    var blockMembers = Set<OcaBlockMember>()
    try await _getActionObjectsRecursiveFallback(&blockMembers)
    return Array(blockMembers).sorted(by: {
      if $1.containerObjectNumber == $0.containerObjectNumber {
        $1.memberObjectIdentification.oNo > $0.memberObjectIdentification.oNo
      } else {
        $1.containerObjectNumber > $0.containerObjectNumber
      }
    })
  }

  public static let addSignalPath = OcaMethodDescription<OcaSignalPath, OcaUint16>(
    "3.7",
    name: "AddSignalPath",
    parameterNames: ["Path"],
    resultNames: ["Index"]
  )

  public func add(signalPath path: OcaSignalPath) async throws -> OcaUint16 {
    try await invoke(Self.addSignalPath, path)
  }

  public static let deleteSignalPath = OcaMethodDescription<OcaUint16, Void>(
    "3.8",
    name: "DeleteSignalPath",
    parameterNames: ["Index"]
  )

  public func delete(signalPath index: OcaUint16) async throws {
    try await invoke(Self.deleteSignalPath, index)
  }

  public static let getSignalPathsRecursive =
    OcaMethodDescription<Void, OcaMap<OcaUint16, OcaSignalPath>>(
      "3.10",
      name: "GetSignalPathsRecursive",
      resultNames: ["SignalPaths"]
    )

  public func getActionObjectsRecursive() async throws -> OcaMap<OcaUint16, OcaSignalPath> {
    try await invoke(Self.getSignalPathsRecursive)
  }

  // 3.12 to 3.14 are the 2018 model's param sets; the device does not answer them
  public static let applyParamSet = OcaMethodDescription<OcaLibVolIdentifier, Void>(
    "3.12",
    name: "ApplyParamSet",
    parameterNames: ["Identifier"]
  )

  public func apply(paramSet identifier: OcaLibVolIdentifier) async throws {
    try await invoke(Self.applyParamSet, identifier)
  }

  public static let getCurrentParamSetData = OcaMethodDescription<Void, OcaLibVolData_ParamSet>(
    "3.13",
    name: "GetCurrentParamSetData",
    resultNames: ["Data"]
  )

  public func get() async throws -> OcaLibVolData_ParamSet {
    try await invoke(Self.getCurrentParamSetData)
  }

  public static let storeCurrentParamSetData = OcaMethodDescription<OcaLibVolIdentifier, Void>(
    "3.14",
    name: "StoreCurrentParamSetData",
    parameterNames: ["Identifier"]
  )

  public func store(currentParamSet identifier: OcaLibVolIdentifier) async throws {
    try await invoke(Self.storeCurrentParamSetData, identifier)
  }

  private func validate(
    _ searchResults: [OcaObjectSearchResult],
    against flags: OcaActionObjectSearchResultFlags
  ) throws {
    var valid = true

    if valid, flags.contains(.oNo) {
      valid = searchResults.allSatisfy { $0.oNo != nil }
    }
    if valid, flags.contains(.classIdentification) {
      valid = searchResults.allSatisfy { $0.classIdentification != nil }
    }
    if valid, flags.contains(.containerPath) {
      valid = searchResults.allSatisfy { $0.containerPath != nil }
    }
    if valid, flags.contains(.role) {
      valid = searchResults.allSatisfy { $0.role != nil }
    }
    // note label is optional
    guard valid else {
      throw Ocp1Error.responseParameterOutOfRange
    }
  }

  public struct FindActionObjectsByRoleParameters: OcaParametersReflectable {
    public let searchName: OcaString
    public let nameComparisonType: OcaStringComparisonType
    public let searchClassID: OcaClassID
    public let resultFlags: OcaActionObjectSearchResultFlags

    public init(
      searchName: OcaString,
      nameComparisonType: OcaStringComparisonType,
      searchClassID: OcaClassID?,
      resultFlags: OcaActionObjectSearchResultFlags
    ) {
      self.searchName = searchName
      self.nameComparisonType = nameComparisonType
      self.searchClassID = searchClassID ?? OcaClassID()
      self.resultFlags = resultFlags
    }
  }

  /// The search results decode by `resultFlags`, passed to the decoder as user info,
  /// which `invoke` has no argument for; so these four send by the descriptor's parts.
  private func search<Parameters: Encodable>(
    _ method: OcaMethodDescription<Parameters, [OcaObjectSearchResult]>,
    _ parameters: Parameters,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> [OcaObjectSearchResult] {
    let searchResults: [OcaObjectSearchResult] = try await sendCommandRrq(
      methodID: method.methodID,
      parameters: parameters,
      parameterNames: method.erased.parameterNames,
      responseNames: method.erased.resultNames,
      userInfo: [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
    )
    try validate(searchResults, against: resultFlags)
    return searchResults
  }

  public static let findActionObjectsByRole =
    OcaMethodDescription<FindActionObjectsByRoleParameters, [OcaObjectSearchResult]>(
      "3.17",
      name: "FindActionObjectsByRole",
      resultNames: ["Result"]
    )

  public func find(
    actionObjectsByRole searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Self.findActionObjectsByRole,
      .init(
        searchName: searchName,
        nameComparisonType: nameComparisonType,
        searchClassID: searchClassID,
        resultFlags: resultFlags
      ),
      resultFlags: resultFlags
    )
  }

  public static let findActionObjectsByRoleRecursive =
    OcaMethodDescription<FindActionObjectsByRoleParameters, [OcaObjectSearchResult]>(
      "3.18",
      name: "FindActionObjectsByRoleRecursive",
      resultNames: ["Result"]
    )

  public func findRecursive(
    actionObjectsByRole searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Self.findActionObjectsByRoleRecursive,
      .init(
        searchName: searchName,
        nameComparisonType: nameComparisonType,
        searchClassID: searchClassID,
        resultFlags: resultFlags
      ),
      resultFlags: resultFlags
    )
  }

  public struct FindActionObjectsByPathParameters: OcaParametersReflectable {
    public let searchPath: OcaNamePath
    public let resultFlags: OcaActionObjectSearchResultFlags

    public init(searchPath: OcaNamePath, resultFlags: OcaActionObjectSearchResultFlags) {
      self.searchPath = searchPath
      self.resultFlags = resultFlags
    }
  }

  public static let findActionObjectsByLabelRecursive =
    OcaMethodDescription<FindActionObjectsByRoleParameters, [OcaObjectSearchResult]>(
      "3.19",
      name: "FindActionObjectsByLabelRecursive",
      resultNames: ["Result"]
    )

  public func findRecursive(
    actionObjectsByLabel searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Self.findActionObjectsByLabelRecursive,
      .init(
        searchName: searchName,
        nameComparisonType: nameComparisonType,
        searchClassID: searchClassID,
        resultFlags: resultFlags
      ),
      resultFlags: resultFlags
    )
  }

  public static let findActionObjectsByRolePath =
    OcaMethodDescription<FindActionObjectsByPathParameters, [OcaObjectSearchResult]>(
      "3.20",
      name: "FindActionObjectsByRolePath",
      resultNames: ["Result"]
    )

  public func find(
    actionObjectsByPath searchPath: OcaNamePath,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Self.findActionObjectsByRolePath,
      .init(searchPath: searchPath, resultFlags: resultFlags),
      resultFlags: resultFlags
    )
  }

  public static let applyParamDataset =
    OcaMethodDescription<OcaONo, Void>("3.23", name: "ApplyParamDataset", parameterNames: ["ONo"])

  public func apply(paramDataset: OcaONo) async throws {
    try await invoke(Self.applyParamDataset, paramDataset)
  }

  public static let storeCurrentParameterData = OcaMethodDescription<OcaONo, Void>(
    "3.24",
    name: "StoreCurrentParameterData",
    parameterNames: ["ONo"]
  )

  public func store(currentParameterData: OcaONo) async throws {
    try await invoke(Self.storeCurrentParameterData, currentParameterData)
  }

  public static let fetchCurrentParameterData = OcaMethodDescription<Void, OcaLongBlob>(
    "3.25",
    name: "FetchCurrentParameterData",
    resultNames: ["Data"]
  )

  public func fetchCurrentParameterData() async throws -> OcaLongBlob {
    try await invoke(Self.fetchCurrentParameterData)
  }

  public static let applyParameterData = OcaMethodDescription<OcaLongBlob, Void>(
    "3.26",
    name: "ApplyParameterData",
    parameterNames: ["Data"]
  )

  public func apply(parameterData: OcaLongBlob) async throws {
    try await invoke(Self.applyParameterData, parameterData)
  }

  @_spi(SwiftOCAPrivate)
  public struct ConstructDataSetParameters: OcaParametersReflectable {
    public let classID: OcaClassID
    public let name: OcaString
    public let type: OcaMimeType
    public let maxSize: OcaUint64
    public let initialContents: OcaLongBlob

    public init(
      classID: OcaClassID,
      name: OcaString,
      type: OcaMimeType,
      maxSize: OcaUint64,
      initialContents: OcaLongBlob
    ) {
      self.classID = classID
      self.name = name
      self.type = type
      self.maxSize = maxSize
      self.initialContents = initialContents
    }
  }

  @_spi(SwiftOCAPrivate) public static let constructDataset =
    OcaMethodDescription<ConstructDataSetParameters, OcaONo>(
      "3.27",
      name: "ConstructDataset",
      resultNames: ["ObjectNumber"]
    )

  public func constructDataset(
    classID: OcaClassID,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob
  ) async throws -> OcaONo {
    try await invoke(
      Self.constructDataset,
      .init(
        classID: classID,
        name: name,
        type: type,
        maxSize: maxSize,
        initialContents: initialContents
      )
    )
  }

  @_spi(SwiftOCAPrivate)
  public struct DuplicateDataSetParameters: OcaParametersReflectable {
    public let oldONo: OcaONo
    public let targetBlockONo: OcaONo
    public let newName: OcaString
    public let newMaxSize: OcaUint64

    public init(oldONo: OcaONo, targetBlockONo: OcaONo, newName: OcaString, newMaxSize: OcaUint64) {
      self.oldONo = oldONo
      self.targetBlockONo = targetBlockONo
      self.newName = newName
      self.newMaxSize = newMaxSize
    }
  }

  @_spi(SwiftOCAPrivate) public static let duplicateDataset =
    OcaMethodDescription<DuplicateDataSetParameters, OcaONo>(
      "3.28",
      name: "DuplicateDataset",
      resultNames: ["NewONo"]
    )

  public func duplicateDataset(
    oldONo: OcaONo,
    targetBlockONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64
  ) async throws -> OcaONo {
    try await invoke(
      Self.duplicateDataset,
      .init(
        oldONo: oldONo,
        targetBlockONo: targetBlockONo,
        newName: newName,
        newMaxSize: newMaxSize
      )
    )
  }

  public static let getDatasetObjectsRecursive =
    OcaMethodDescription<Void, OcaList<OcaBlockMember>>(
      "3.30",
      name: "GetDatasetObjectsRecursive",
      resultNames: ["Objects"]
    )

  public func getDatasetObjectsRecursive() async throws -> OcaList<OcaBlockMember> {
    try await invoke(Self.getDatasetObjectsRecursive)
  }

  @_spi(SwiftOCAPrivate)
  public struct FindDatasetsParameters: OcaParametersReflectable {
    public let name: OcaString
    public let nameComparisonType: OcaStringComparisonType
    public let type: OcaMimeType
    public let typeComparisonType: OcaStringComparisonType

    public init(
      name: OcaString,
      nameComparisonType: OcaStringComparisonType,
      type: OcaMimeType,
      typeComparisonType: OcaStringComparisonType
    ) {
      self.name = name
      self.nameComparisonType = nameComparisonType
      self.type = type
      self.typeComparisonType = typeComparisonType
    }
  }

  @_spi(SwiftOCAPrivate) public static let findDatasets =
    OcaMethodDescription<FindDatasetsParameters, [OcaDatasetSearchResult]>(
      "3.31",
      name: "FindDatasets",
      resultNames: ["Datasets"]
    )

  public func findDatasets(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType
  ) async throws
    -> [OcaDatasetSearchResult]
  {
    try await invoke(
      Self.findDatasets,
      .init(
        name: name,
        nameComparisonType: nameComparisonType,
        type: type,
        typeComparisonType: typeComparisonType
      )
    )
  }

  @_spi(SwiftOCAPrivate) public static let findDatasetsRecursive =
    OcaMethodDescription<FindDatasetsParameters, [OcaDatasetSearchResult]>(
      "3.32",
      name: "FindDatasetsRecursive",
      resultNames: ["Datasets"]
    )

  public func findDatasetsRecursive(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType
  ) async throws
    -> [OcaDatasetSearchResult]
  {
    try await invoke(
      Self.findDatasetsRecursive,
      .init(
        name: name,
        nameComparisonType: nameComparisonType,
        type: type,
        typeComparisonType: typeComparisonType
      )
    )
  }

  override public var isContainer: Bool {
    true
  }

  #if NonEmbeddedBuild
  override open func getJsonValue(
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async -> [String: any Sendable] {
    var jsonObject = await super.getJsonValue(flags: flags)
    // the property carries object identifications; the dump carries the objects
    // themselves, under that same property's name
    jsonObject[_jsonPropertyName(for: $actionObjects.propertyID)] =
      try? await resolveActionObjects()
      .asyncMap { await $0.getJsonValue(flags: flags) }
    return jsonObject
  }
  #endif
}

public extension OcaBlock {
  @OcaConnectionActor
  func resolveActionObjects() async throws -> [OcaRoot] {
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

    return try await _actionObjects.onCompletion(self) { actionObjects in
      try await actionObjects.asyncCompactMap {
        try await connectionDelegate.resolve(object: $0, owner: self.objectNumber)
      }
    }
  }

  private func addConfigurableBlockSubscriptions() async throws {
    do {
      let configurability = try await $configurability._getValue(
        self,
        flags: [.returnCachedValue, .cacheValue]
      )
      if configurability.contains(.actionObjects) {
        await $actionObjects.subscribe(self)
      }
      if configurability.contains(.datasetObjects) {
        // FIXME: implement
      }
      if configurability.contains(.signalPaths) {
        await $signalPaths.subscribe(self)
      }
    } catch Ocp1Error.status(.notImplemented) {}
  }

  @OcaConnectionActor
  func resolveActionObjectsRecursive() async throws
    -> [OcaContainerObjectMember]
  {
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
    let recursiveMembers: [OcaBlockMember]
    do {
      /// don't use recursive methods with UDP because they can exceed the minimum PDU size
      guard !connectionDelegate.isDatagram else {
        throw Ocp1Error.status(.notImplemented)
      }
      recursiveMembers = try await getActionObjectsRecursive()
    } catch Ocp1Error.status(.notImplemented) {
      recursiveMembers = try await getActionObjectsRecursiveFallback()
    }
    var containerMembers: [OcaContainerObjectMember]

    containerMembers = try recursiveMembers.compactMap { member in
      let memberObject = try connectionDelegate.resolve(
        object: member.memberObjectIdentification,
        owner: member.containerObjectNumber
      )
      return OcaContainerObjectMember(
        memberObject: memberObject,
        containerObjectNumber: member.containerObjectNumber
      )
    }

    for container in connectionDelegate.objects.compactMap({ $0.value as? OcaBlock }) {
      container._set(actionObjects: containerMembers.filter {
        $0.containerObjectNumber == container.objectNumber
      }.map(\.memberObject.objectIdentification))
      try? await container.addConfigurableBlockSubscriptions()
    }

    return containerMembers
  }

  @OcaConnectionActor
  func getRoleMap(separator: String = "/") async throws -> [String: OcaRoot] {
    let members = try await resolveActionObjectsRecursive()

    return try await [String: OcaRoot](uniqueKeysWithValues: members.asyncMap { @Sendable in
      try await ($0.memberObject._getRolePath().joined(separator: separator), $0.memberObject)
    })
  }
}

extension OcaBlock {
  func _set(actionObjects: [OcaObjectIdentification]) {
    self.$actionObjects.subject.send(.success(actionObjects))
  }
}

public extension Array where Element: OcaRoot {
  var hasContainerMembers: Bool {
    allSatisfy(\.isContainer)
  }
}
