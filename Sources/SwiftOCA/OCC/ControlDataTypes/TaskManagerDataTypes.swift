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

public enum OcaTaskManagerState: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case enabled = 1
  case disabled = 2
}

public typealias OcaTaskID = OcaUint32

public typealias OcaTaskGroupID = OcaUint16

public enum OcaTaskState: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case notPrepared = 1
  case disabled = 2
  case enabled = 3
  case running = 4
  case completed = 5
  case failed = 6
  case stopped = 7
  case aborted = 8
}

public struct OcaTaskStatus: Codable, Sendable {
  public let id: OcaTaskID
  public let state: OcaTaskState
  public let errorCode: OcaUint16

  public init(id: OcaTaskID, state: OcaTaskState, errorCode: OcaUint16) {
    self.id = id
    self.state = state
    self.errorCode = errorCode
  }
}

public struct OcaTask: Codable, Sendable {
  public let id: OcaTaskID
  public let label: OcaString
  public let programID: OcaLibVolIdentifier
  public let groupID: OcaTaskGroupID
  public let timeMode: OcaTimeMode
  public let timeSourceONo: OcaONo
  public let startTime: OcaTimePTP
  public let duration: OcaTimePTP
  public let applicationSpecificParameters: OcaBlob
}
