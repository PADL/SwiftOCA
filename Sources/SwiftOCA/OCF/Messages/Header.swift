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

public let Ocp1SyncValue: OcaUint8 = 0x3B
public let Ocp1ProtocolVersion1: OcaUint16 = 1
public let Ocp1ProtocolVersion: OcaUint16 = Ocp1ProtocolVersion1

public struct Ocp1Header: Codable, Sendable {
  public var protocolVersion: OcaUint16
  public var pduSize: OcaUint32
  public var pduType: OcaMessageType
  public var messageCount: OcaUint16

  init(pduType: OcaMessageType, messageCount: OcaUint16) {
    protocolVersion = Ocp1ProtocolVersion
    pduSize = 0
    self.pduType = pduType
    self.messageCount = messageCount
  }

  init() {
    self.init(pduType: .ocaKeepAlive, messageCount: 0)
  }
}

public protocol Ocp1MessagePdu: Codable, Sendable {
  var syncVal: OcaUint8 { get }
  var header: Ocp1Header { get }
}

public protocol Ocp1Message: Codable, Sendable {
  var messageSize: OcaUint32 { get }
}
