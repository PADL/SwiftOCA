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

open class OcaLockManager: OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.3.14") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  public struct LockWaitParameters: OcaParametersReflectable {
    public let target: OcaONo
    public let type: OcaLockState
    public let timeout: OcaTimeInterval
  }

  public static let lockWait =
    OcaMethodDescriptor<LockWaitParameters, Void>("3.1", name: "LockWait")

  public func lockWait(
    target: OcaONo,
    type: OcaLockState,
    timeout: OcaTimeInterval
  ) async throws {
    try await invoke(Self.lockWait, .init(target: target, type: type, timeout: timeout))
  }

  public static let abortWaits =
    OcaMethodDescriptor<OcaONo, Void>("3.2", name: "AbortWaits", parameterNames: ["ONo"])

  public func abortWaits(oNo: OcaONo) async throws {
    try await invoke(Self.abortWaits, oNo)
  }

  public convenience init() {
    self.init(objectNumber: OcaLockManagerONo)
  }
}
