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

open class OcaSecurityManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.2") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var secureControlData: OcaProperty<OcaBoolean>.PropertyValue

  public convenience init() {
    self.init(objectNumber: OcaSecurityManagerONo)
  }

  public func enableControlSecurity() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.1"))
  }

  public func disableControlSecurity() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.2"))
  }

  public struct AddPreSharedKeyParameters: Ocp1ParametersReflectable {
    public let identity: OcaString
    public let key: OcaBlob

    public init(identity: OcaString, key: OcaBlob) {
      self.identity = identity
      self.key = key
    }
  }

  public func changePreSharedKey(identity: OcaString, key: OcaBlob) async throws {
    let parameters = AddPreSharedKeyParameters(identity: identity, key: key)
    try await sendCommandRrq(methodID: OcaMethodID("3.3"), parameters: parameters)
  }

  public func addPreSharedKey(identity: OcaString, key: OcaBlob) async throws {
    let parameters = AddPreSharedKeyParameters(identity: identity, key: key)
    try await sendCommandRrq(methodID: OcaMethodID("3.4"), parameters: parameters)
  }

  public func deletePreSharedKey(identity: OcaString) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.5"), parameters: identity)
  }
}
