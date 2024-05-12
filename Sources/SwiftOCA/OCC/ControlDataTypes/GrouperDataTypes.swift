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

public struct OcaGrouperGroup: Codable, Sendable {
  public let index: OcaUint16
  public let name: OcaString
  public let proxyONo: OcaONo

  public init(index: OcaUint16, name: OcaString, proxyONo: OcaONo) {
    self.index = index
    self.name = name
    self.proxyONo = proxyONo
  }
}

public struct OcaGrouperCitizen: Codable, Sendable {
  public let index: OcaUint16
  public let objectPath: OcaOPath
  public let online: OcaBoolean

  public init(index: OcaUint16, objectPath: OcaOPath, online: OcaBoolean) {
    self.index = index
    self.objectPath = objectPath
    self.online = online
  }
}

public enum OcaGrouperMode: OcaUint8, Codable, Sendable, CaseIterable {
  case masterSlave = 1
  case peerToPeer = 2
}

public struct OcaGrouperEnrollment: Codable, Sendable {
  public let groupIndex: OcaUint16
  public let citizenIndex: OcaUint16

  public init(groupIndex: OcaUint16, citizenIndex: OcaUint16) {
    self.groupIndex = groupIndex
    self.citizenIndex = citizenIndex
  }
}
