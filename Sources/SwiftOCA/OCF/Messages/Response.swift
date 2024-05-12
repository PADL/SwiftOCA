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

public struct Ocp1Response: Ocp1Message, Codable, Sendable {
  public let responseSize: OcaUint32
  public let handle: OcaUint32
  public let statusCode: OcaStatus
  public let parameters: Ocp1Parameters

  public var messageSize: OcaUint32 { responseSize }

  public init(
    responseSize: OcaUint32 = 0,
    handle: OcaUint32 = 0,
    statusCode: OcaStatus = .ok,
    parameters: Ocp1Parameters = Ocp1Parameters()
  ) {
    self.responseSize = responseSize
    self.handle = handle
    self.statusCode = statusCode
    self.parameters = parameters
  }
}
