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

@OcaMethods
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

  @OcaMethod("3.1", name: "EnableControlSecurity")
  public func enableControlSecurity() async throws

  @OcaMethod("3.2", name: "DisableControlSecurity")
  public func disableControlSecurity() async throws

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

  @OcaMethod("3.3", name: "ChangePreSharedKey", parameters: ChangePreSharedKeyParameters.self)
  public func changePreSharedKey(identity: OcaString, newKey: OcaBlob) async throws

  @OcaMethod("3.4", name: "AddPreSharedKey", parameters: AddPreSharedKeyParameters.self)
  public func addPreSharedKey(identity: OcaString, key: OcaBlob) async throws

  @OcaMethod("3.5", name: "DeletePreSharedKey", parameterNames: ["Identity"])
  public func deletePreSharedKey(identity: OcaString) async throws
}
