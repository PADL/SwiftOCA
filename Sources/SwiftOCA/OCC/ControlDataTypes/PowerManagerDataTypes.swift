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

public enum OcaPowerState: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case working = 1
  case standby = 2
  case off = 3
}

public enum OcaPowerSupplyType: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case mains = 1
  case battery = 2
  /// includes Power-over-Ethernet supplies
  case phantom = 3
  case solar = 4
}

public enum OcaPowerSupplyState: OcaUint8, Codable, Sendable, CaseIterable {
  case off = 0
  /// turned on, but not available for activation
  case unavailable = 1
  case available = 2
  /// currently supplying power to the device
  case active = 3
}

public enum OcaPowerSupplyLocation: OcaUint8, Codable, Sendable, CaseIterable {
  case unspecified = 1
  case `internal` = 2
  case external = 3
}
