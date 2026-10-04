//
// Copyright (c) 2024 PADL Software Pty Ltd
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

open class OcaSecurityManager: OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID {
    OcaClassID("1.3.2")
  }

  override open class var classVersion: OcaClassVersionNumber {
    3
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var secureControlData: OcaProperty<OcaBoolean>.PropertyValue

  public convenience init() {
    self.init(objectNumber: OcaSecurityManagerONo)
  }

  public static let enableControlSecurity =
    OcaMethodDescription<Void, Void>("3.1", name: "EnableControlSecurity")

  public func enableControlSecurity() async throws {
    try await invoke(Self.enableControlSecurity)
  }

  public static let disableControlSecurity =
    OcaMethodDescription<Void, Void>("3.2", name: "DisableControlSecurity")

  public func disableControlSecurity() async throws {
    try await invoke(Self.disableControlSecurity)
  }

  public struct AddPreSharedKeyParameters: OcaParametersReflectable {
    public let identity: OcaString
    public let key: OcaBlob

    public init(identity: OcaString, key: OcaBlob) {
      self.identity = identity
      self.key = key
    }
  }

  public struct ChangePreSharedKeyParameters: OcaParametersReflectable {
    public let identity: OcaString
    public let newKey: OcaBlob

    public init(identity: OcaString, newKey: OcaBlob) {
      self.identity = identity
      self.newKey = newKey
    }
  }

  public static let changePreSharedKey =
    OcaMethodDescription<ChangePreSharedKeyParameters, Void>("3.3", name: "ChangePreSharedKey")

  public func changePreSharedKey(identity: OcaString, key: OcaBlob) async throws {
    try await invoke(Self.changePreSharedKey, .init(identity: identity, newKey: key))
  }

  public static let addPreSharedKey =
    OcaMethodDescription<AddPreSharedKeyParameters, Void>("3.4", name: "AddPreSharedKey")

  public func addPreSharedKey(identity: OcaString, key: OcaBlob) async throws {
    try await invoke(Self.addPreSharedKey, .init(identity: identity, key: key))
  }

  public static let deletePreSharedKey = OcaMethodDescription<OcaString, Void>(
    "3.5",
    name: "DeletePreSharedKey",
    parameterNames: ["Identity"]
  )

  public func deletePreSharedKey(identity: OcaString) async throws {
    try await invoke(Self.deletePreSharedKey, identity)
  }
}
