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

open class OcaBlock: OcaWorker, @unchecked Sendable {
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

  @OcaProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.21")
  )
  public var configurability: OcaProperty<OcaBlockConfigurability>.PropertyValue

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

  public func getActionObjectsRecursive() async throws -> OcaList<OcaBlockMember> {
    try await sendCommandRrq(methodID: OcaMethodID("3.6"))
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

  public func getActionObjectsRecursive() async throws -> OcaMap<OcaUint16, OcaSignalPath> {
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

  public struct FindActionObjectsByRoleParameters: Ocp1ParametersReflectable {
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

  public func find(
    actionObjectsByRole searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    let params = FindActionObjectsByRoleParameters(
      searchName: searchName,
      nameComparisonType: nameComparisonType,
      searchClassID: searchClassID,
      resultFlags: resultFlags
    )
    let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
    let searchResults: [OcaObjectSearchResult] = try await sendCommandRrq(
      methodID: OcaMethodID("3.17"),
      parameters: params,
      userInfo: userInfo
    )
    try validate(searchResults, against: resultFlags)
    return searchResults
  }

  public func findRecursive(
    actionObjectsByRole searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    let params = FindActionObjectsByRoleParameters(
      searchName: searchName,
      nameComparisonType: nameComparisonType,
      searchClassID: searchClassID,
      resultFlags: resultFlags
    )
    let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
    let searchResults: [OcaObjectSearchResult] = try await sendCommandRrq(
      methodID: OcaMethodID("3.18"),
      parameters: params,
      userInfo: userInfo
    )
    try validate(searchResults, against: resultFlags)
    return searchResults
  }

  public struct FindActionObjectsByPathParameters: Ocp1ParametersReflectable {
    public let searchPath: OcaNamePath
    public let resultFlags: OcaActionObjectSearchResultFlags

    public init(searchPath: OcaNamePath, resultFlags: OcaActionObjectSearchResultFlags) {
      self.searchPath = searchPath
      self.resultFlags = resultFlags
    }
  }

  public func findRecursive(
    actionObjectsByLabel searchName: OcaString,
    nameComparisonType: OcaStringComparisonType,
    searchClassID: OcaClassID? = nil,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    let params = FindActionObjectsByRoleParameters(
      searchName: searchName,
      nameComparisonType: nameComparisonType,
      searchClassID: searchClassID,
      resultFlags: resultFlags
    )
    let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
    let searchResults: [OcaObjectSearchResult] = try await sendCommandRrq(
      methodID: OcaMethodID("3.19"),
      parameters: params,
      userInfo: userInfo
    )
    try validate(searchResults, against: resultFlags)
    return searchResults
  }

  public func find(
    actionObjectsByPath searchPath: OcaNamePath,
    resultFlags: OcaActionObjectSearchResultFlags
  ) async throws -> OcaList<OcaObjectSearchResult> {
    let params = FindActionObjectsByPathParameters(
      searchPath: searchPath,
      resultFlags: resultFlags
    )
    let userInfo = [OcaObjectSearchResult.FlagsUserInfoKey: resultFlags]
    let searchResults: [OcaObjectSearchResult] = try await sendCommandRrq(
      methodID: OcaMethodID("3.20"),
      parameters: params,
      userInfo: userInfo
    )
    try validate(searchResults, against: resultFlags)
    return searchResults
  }

  override public var isContainer: Bool {
    true
  }

  override open func getJsonValue(
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async -> [String: Any] {
    var jsonObject = await super.getJsonValue(flags: flags)
    jsonObject["3.2"] = try? await resolveActionObjects()
      .asyncMap { await $0.getJsonValue(flags: flags) }
    return jsonObject
  }
}

public extension OcaBlock {
  @OcaConnection
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

  @OcaConnection
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

  @OcaConnection
  func getRoleMap(separator: String = "/") async throws -> [String: OcaRoot] {
    let members = try await resolveActionObjectsRecursive()

    return try await [String: OcaRoot](uniqueKeysWithValues: members.asyncMap {
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
