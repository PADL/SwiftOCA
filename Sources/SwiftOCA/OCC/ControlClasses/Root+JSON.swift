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

import AnyCodable
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

package extension JSONEncoder {
  func reencodeAsValidJSONObject<Value: Codable>(_ value: some Codable) throws -> Value {
    let data = try encode(value)
    return try JSONDecoder().decode(Value.self, from: data)
  }

  func reencodeAsValidJSONObject(_ value: some Codable) throws -> Any {
    let data = try encode(value)
    return try JSONDecoder().decode(AnyDecodable.self, from: data).value
  }
}
