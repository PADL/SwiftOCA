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

open class OcaLog: OcaDataset, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.5.1") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.7"),
    setMethodID: OcaMethodID("3.8")
  )
  public var enabled: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2"),
    setMethodID: OcaMethodID("3.3")
  )
  public var severityThreshold: OcaProperty<OcaLogSeverityLevel>.PropertyValue

  public func add(logRecord entry: OcaLogRecord) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.1"),
      parameters: entry
    )
  }

  // 3.4 OpenRetrievalSession
  // 3.5 CloseRetrievalSession
  // 3.6 RetrieveRecords
}
