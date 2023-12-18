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

open class OcaLockManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.14") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    public struct LockWaitParameters: Codable {
        public let target: OcaONo
        public let type: OcaLockState
        public let timeout: OcaTimeInterval
    }

    public func lockWait(
        target: OcaONo,
        type: OcaLockState,
        timeout: OcaTimeInterval
    ) async throws {
        let params = LockWaitParameters(target: target, type: type, timeout: timeout)
        try await sendCommandRrq(methodID: OcaMethodID("3.1"), parameters: params)
    }

    public func abortWaits(oNo: OcaONo) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.2"), parameters: oNo)
    }

    public convenience init() {
        self.init(objectNumber: OcaLockManagerONo)
    }
}
