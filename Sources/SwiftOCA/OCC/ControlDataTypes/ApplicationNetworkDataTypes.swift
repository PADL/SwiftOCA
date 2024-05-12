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

public enum OcaApplicationNetworkCommand: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case prepare = 1
  case start = 2
  case pause = 3
  case stop = 4
  case reset = 5
}

public enum OcaApplicationNetworkState: OcaUint8, Codable, Sendable, CaseIterable {
  case unknown = 0
  case notReady = 1
  case readying = 2
  case ready = 3
  case running = 4
  case paused = 5
  case stopping = 6
  case stopped = 7
  case fault = 8
}

public typealias OcaApplicationNetworkServiceID = OcaBlob

public enum OcaProtocolVersion: OcaUint16, Codable, Sendable {
  // Original standard (AES70-2015)
  case aes70_2015 = 1
  // 2018 revision
  case aes70_2018 = 2
  // 2023 revision
  case aes70_2023 = 3
}
