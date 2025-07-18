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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

open class OcaEventHandler: OcaAgent, @unchecked
Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.2.5") }

  func onEvent(context: OcaBlob, eventData: Ocp1EventData) async throws -> OcaStatus {
    .notImplemented
  }
}

protocol OcaPropertyChangeEventNotifiable: OcaPropertySubjectRepresentable {
  func onEvent(_ object: OcaRoot, event: OcaEvent, eventData: Data) throws
}
