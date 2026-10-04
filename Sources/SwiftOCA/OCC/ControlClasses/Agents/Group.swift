//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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

open class OcaGroup: OcaAgent, @unchecked
Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.2.22") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var members: OcaListProperty<OcaONo>.PropertyValue

  // the property's accessors, as the device declares them; OcaGroup is not in the 2023 model
  public static let getMembers =
    OcaMethodDescription<Void, [OcaONo]>("3.1", name: "GetMembers", resultNames: ["Members"])
  public static let setMembers =
    OcaMethodDescription<[OcaONo], Void>("3.2", name: "SetMembers", parameterNames: ["Members"])

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.5"),
    setMethodID: OcaMethodID("3.6")
  )
  public var groupController: OcaProperty<OcaONo>.PropertyValue

  public static let getGroupController = OcaMethodDescription<Void, OcaONo>(
    "3.5",
    name: "GetGroupController",
    resultNames: ["GroupController"]
  )

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.7"),
    setMethodID: OcaMethodID("3.8")
  )
  public var aggregationMode: OcaProperty<OcaString?>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.9"),
    setMethodID: OcaMethodID("3.10")
  )
  public var saturationMode: OcaProperty<OcaString?>.PropertyValue

  public static let addMember =
    OcaMethodDescription<OcaONo, Void>("3.3", name: "AddMember", parameterNames: ["Member"])

  public func add(member objectNumber: OcaONo) async throws {
    try await invoke(Self.addMember, objectNumber)
  }

  public static let deleteMember =
    OcaMethodDescription<OcaONo, Void>("3.4", name: "DeleteMember", parameterNames: ["Member"])

  public func delete(member objectNumber: OcaONo) async throws {
    try await invoke(Self.deleteMember, objectNumber)
  }
}

public extension OcaGroup {
  @OcaConnectionActor
  func resolveMembers<T: OcaRoot>() async throws -> [T] {
    let groupController: OcaRoot? = try? await resolveGroupController()
    return try await resolveMembers(with: groupController)
  }

  @OcaConnectionActor
  func resolveMembers<T: OcaRoot>(with groupController: OcaRoot?) async throws -> [T] {
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

    return try await _members.onCompletion(self) { members in
      var resolved = [T]()
      let groupControllerClassID = groupController.map {
        type(of: $0).classIdentification
      }

      for member in members {
        let classIdentification: OcaClassIdentification
        if let groupControllerClassID {
          classIdentification = groupControllerClassID
        } else {
          classIdentification = try await connectionDelegate
            .getClassIdentification(objectNumber: member)
        }
        let objectID = OcaObjectIdentification(
          oNo: member,
          classIdentification: classIdentification
        )
        guard let member = try await connectionDelegate.resolve(object: objectID) as? T
        else {
          throw Ocp1Error.invalidObject(member)
        }
        resolved.append(member)
      }

      return resolved
    }
  }

  @OcaConnectionActor
  func resolveGroupController<T: OcaRoot>() async throws -> T {
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

    return try await _groupController.onCompletion(self) { groupControllerObjectNumber in
      let classIdentification = try await connectionDelegate
        .getClassIdentification(objectNumber: groupControllerObjectNumber)
      let objectID = OcaObjectIdentification(
        oNo: groupControllerObjectNumber,
        classIdentification: classIdentification
      )
      let resolvedProxy = try await connectionDelegate.resolve(object: objectID) as? T
      guard let resolvedProxy else {
        throw Ocp1Error.proxyResolutionFailed
      }
      return resolvedProxy
    }
  }
}
