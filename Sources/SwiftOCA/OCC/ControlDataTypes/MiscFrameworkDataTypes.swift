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

public enum OcaUnitOfMeasure: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case hertz = 1
  case degreeCelsius = 2
  case volt = 3
  case ampere = 4
  case ohm = 5
}

public typealias OcaAdaptationData = OcaBlob
