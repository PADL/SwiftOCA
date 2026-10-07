//
// Copyright (c) 2026 PADL Software Pty Ltd
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

/// A class manager, which AES70 does not define: it describes the classes of the
/// device's objects. It is PADL's, at the last object number AES70 reserves.
@OcaClass
open class OcaClassManager: OcaManager, @unchecked Sendable {
  /// The organisation whose class this is, until it has a standard home.
  public static let authority = OcaOrganizationID((0x0A, 0xE9, 0x1B))

  override open class var classID: OcaClassID {
    OcaClassID(parent: OcaManager.classID, authority: authority, "1")
  }

  /// The last object number AES70 reserves, which OCA gives no object of its own.
  public static let objectNumber: OcaONo = OcaMaximumReservedONo

  public struct GetControlClassParameters: OcaParametersReflectable {
    public let classID: OcaClassID
    public let includeInherited: OcaBoolean

    public init(classID: OcaClassID, includeInherited: OcaBoolean) {
      self.classID = classID
      self.includeInherited = includeInherited
    }
  }

  /// One class of an object of the device, with its ancestors' elements if asked for.
  @OcaMethod("3.1", name: "GetControlClass", parameters: GetControlClassParameters.self, resultNames: ["Descriptor"])
  public func getControlClass(classID: OcaClassID, includeInherited: OcaBoolean) async throws -> OcaClassDescriptor

  /// Every class of the device's objects, each once and with only its own elements, in
  /// no particular order.
  @OcaMethod("3.2", name: "GetControlClasses", resultNames: ["Descriptors"])
  public func getControlClasses() async throws -> [OcaClassDescriptor]

  public convenience init() {
    self.init(objectNumber: Self.objectNumber)
  }
}
