//
// Copyright (c) 2025 PADL Software Pty Ltd
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

public struct OcaLogRecord: Codable, Sendable {
  public let functionalCategory: OcaUint32
  public let severity: OcaLogSeverityLevel
  public let emitterONo: OcaONo
  public let timestamp: OcaTime
  public let payload: OcaBlob

  public init(
    functionalCategory: OcaUint32,
    severity: OcaLogSeverityLevel,
    emitterONo: OcaONo,
    timestamp: OcaTime,
    payload: OcaBlob
  ) {
    self.functionalCategory = functionalCategory
    self.severity = severity
    self.emitterONo = emitterONo
    self.timestamp = timestamp
    self.payload = payload
  }
}

public struct OcaLogFilter: Codable, Sendable {
  public let functionalCategory: OcaUint32
  public let severityRange: OcaInterval<OcaLogSeverityLevel>
  public let emitterONo: OcaONo
  public let timestampRange: OcaInterval<OcaTime>

  public init(
    functionalCategory: OcaUint32,
    severityRange: OcaInterval<OcaLogSeverityLevel>,
    emitterONo: OcaONo,
    timestampRange: OcaInterval<OcaTime>
  ) {
    self.functionalCategory = functionalCategory
    self.severityRange = severityRange
    self.emitterONo = emitterONo
    self.timestampRange = timestampRange
  }
}

public typealias OcaLogSeverityLevel = OcaInt32
