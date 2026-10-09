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

@OcaClass
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
  @OcaMethod("3.5", name: "GetActionObjects", resultNames: ["Objects"])
  public func getActionObjects() async throws -> [OcaObjectIdentification]

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

  @OcaMethod("3.29", name: "GetDatasetObjects", resultNames: ["Objects"])
  public func getDatasetObjects() async throws -> [OcaObjectIdentification]

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

  @OcaMethod(
    "3.2",
    name: "ConstructActionObject",
    parameters: ConstructActionObjectParameters.self,
    resultNames: ["ObjectNumber"]
  )
  public func constructActionObject(
    classID: OcaClassID,
    constructionParameters: [OcaConstructionParameter]
  ) async throws -> OcaONo

  @OcaMethod(
    "3.3",
    name: "ConstructBlockUsingFactory",
    parameterNames: ["FactoryONo"],
    resultNames: ["ObjectNumber"]
  )
  public func constructBlockUsingFactory(factoryONo: OcaONo) async throws -> OcaONo

  @OcaMethod("3.4", name: "DeleteMember", parameterNames: ["ObjectNumber"])
  public func deleteMember(objectNumber: OcaONo) async throws

  @OcaMethod("3.6", name: "GetActionObjectsRecursive", resultNames: ["Objects"])
  public func getActionObjectsRecursive() async throws -> OcaList<OcaBlockMember>

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

  @OcaMethod("3.7", name: "AddSignalPath", parameterNames: ["Path"], resultNames: ["Index"])
  public func addSignalPath(path: OcaSignalPath) async throws -> OcaUint16

  @OcaMethod("3.8", name: "DeleteSignalPath", parameterNames: ["Index"])
  public func deleteSignalPath(index: OcaUint16) async throws

  @OcaMethod("3.10", name: "GetSignalPathsRecursive", resultNames: ["SignalPaths"])
  public func getSignalPathsRecursive() async throws -> OcaMap<OcaUint16, OcaSignalPath>

  // 3.12 to 3.14 are the 2018 model's param sets; the device does not answer them
  @OcaMethod("3.12", name: "ApplyParamSet", parameterNames: ["Identifier"], deprecated: true)
  public func applyParamSet(identifier: OcaLibVolIdentifier) async throws

  @OcaMethod("3.13", name: "GetCurrentParamSetData", resultNames: ["Data"], deprecated: true)
  public func getCurrentParamSetData() async throws -> OcaLibVolData_ParamSet

  @OcaMethod("3.14", name: "StoreCurrentParamSetData", parameterNames: ["Identifier"], deprecated: true)
  public func storeCurrentParamSetData(identifier: OcaLibVolIdentifier) async throws

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

  /// The search results decode by `resultFlags`, which the decoder reads as user info.
  private func search<Parameters: Encodable>(
    _ method: OcaMethodDescriptor<Parameters, [OcaObjectSearchResult]>,
    _ parameters: Parameters,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> [OcaObjectSearchResult] {
    let searchResults = try await invoke(
      method,
      parameters,
      userInfo: [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
    )
    try validate(searchResults, against: resultFlags)
    return searchResults
  }

  @OcaMethodDescriptor(
    "3.17",
    name: "FindActionObjectsByRole",
    parameters: FindActionObjectsByRoleParameters.self,
    result: [OcaObjectSearchResult].self,
    resultNames: ["Result"]
  )
  public func findActionObjectsByRole(
    searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Methods.findActionObjectsByRole,
      .init(
        searchName: searchName,
        nameComparisonType: nameComparisonType,
        searchClassID: searchClassID,
        resultFlags: resultFlags
      ),
      resultFlags: resultFlags
    )
  }

  @OcaMethodDescriptor(
    "3.18",
    name: "FindActionObjectsByRoleRecursive",
    parameters: FindActionObjectsByRoleParameters.self,
    result: [OcaObjectSearchResult].self,
    resultNames: ["Result"]
  )
  public func findActionObjectsByRoleRecursive(
    searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Methods.findActionObjectsByRoleRecursive,
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

  @OcaMethodDescriptor(
    "3.19",
    name: "FindActionObjectsByLabelRecursive",
    parameters: FindActionObjectsByRoleParameters.self,
    result: [OcaObjectSearchResult].self,
    resultNames: ["Result"]
  )
  public func findActionObjectsByLabelRecursive(
    searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Methods.findActionObjectsByLabelRecursive,
      .init(
        searchName: searchName,
        nameComparisonType: nameComparisonType,
        searchClassID: searchClassID,
        resultFlags: resultFlags
      ),
      resultFlags: resultFlags
    )
  }

  @OcaMethodDescriptor(
    "3.20",
    name: "FindActionObjectsByRolePath",
    parameters: FindActionObjectsByPathParameters.self,
    result: [OcaObjectSearchResult].self,
    resultNames: ["Result"]
  )
  public func findActionObjectsByRolePath(
    searchPath: OcaNamePath,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    try await search(
      Methods.findActionObjectsByRolePath,
      .init(searchPath: searchPath, resultFlags: resultFlags),
      resultFlags: resultFlags
    )
  }

  @OcaMethod("3.23", name: "ApplyParamDataset", parameterNames: ["ONo"])
  public func applyParamDataset(oNo: OcaONo) async throws

  @OcaMethod("3.24", name: "StoreCurrentParameterData", parameterNames: ["ONo"])
  public func storeCurrentParameterData(oNo: OcaONo) async throws

  @OcaMethod("3.25", name: "FetchCurrentParameterData", resultNames: ["Data"])
  public func fetchCurrentParameterData() async throws -> OcaLongBlob

  @OcaMethod("3.26", name: "ApplyParameterData", parameterNames: ["Data"])
  public func applyParameterData(data: OcaLongBlob) async throws

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

  @OcaMethod(
    "3.27",
    name: "ConstructDataset",
    parameters: ConstructDataSetParameters.self,
    resultNames: ["ObjectNumber"]
  )
  public func constructDataset(
    classID: OcaClassID,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob
  ) async throws -> OcaONo

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

  @OcaMethod(
    "3.28",
    name: "DuplicateDataset",
    parameters: DuplicateDataSetParameters.self,
    resultNames: ["NewONo"]
  )
  public func duplicateDataset(
    oldONo: OcaONo,
    targetBlockONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64
  ) async throws -> OcaONo

  @OcaMethod("3.30", name: "GetDatasetObjectsRecursive", resultNames: ["Objects"])
  public func getDatasetObjectsRecursive() async throws -> OcaList<OcaBlockMember>

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

  @OcaMethod(
    "3.31",
    name: "FindDatasets",
    parameters: FindDatasetsParameters.self,
    resultNames: ["Datasets"]
  )
  public func findDatasets(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType
  ) async throws
    -> [OcaDatasetSearchResult]


  @OcaMethod(
    "3.32",
    name: "FindDatasetsRecursive",
    parameters: FindDatasetsParameters.self,
    resultNames: ["Datasets"]
  )
  public func findDatasetsRecursive(
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
    type: OcaMimeType,
    typeComparisonType: OcaStringComparisonType
  ) async throws
    -> [OcaDatasetSearchResult]


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
