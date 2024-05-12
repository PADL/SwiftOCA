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

public struct Ocp1KeepAlive1: Ocp1Message, Codable, Sendable {
  public let heartBeatTime: OcaUint16 // sec

  public var messageSize: OcaUint32 { 2 }

  public init(heartBeatTime: OcaUint16) {
    self.heartBeatTime = heartBeatTime
  }
}

public struct Ocp1KeepAlive2: Ocp1Message, Codable, Sendable {
  public let heartBeatTime: OcaUint32 // msec

  public var messageSize: OcaUint32 { 4 }

  public init(heartBeatTime: OcaUint32) {
    self.heartBeatTime = heartBeatTime
  }
}

public typealias Ocp1KeepAlive = Ocp1KeepAlive1

public extension Ocp1KeepAlive {
  static func keepAlive(interval heartbeatTime: Duration) -> Ocp1Message {
    let seconds = heartbeatTime.seconds
    return Ocp1KeepAlive1(heartBeatTime: OcaUint16(seconds == 0 ? 1 : seconds))
  }
}

private extension Duration {
  var seconds: Int64 {
    components.seconds
  }

  var milliseconds: Int64 {
    components.seconds * 1000 + Int64(Double(components.attoseconds) * 1e-15)
  }
}
