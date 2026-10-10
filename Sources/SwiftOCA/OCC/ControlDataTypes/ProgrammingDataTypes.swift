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

public enum OcaRelationalOperator: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case equality = 1
  case inequality = 2
  case greaterThan = 3
  case greaterThanOrEqual = 4
  case lessThan = 5
  case lessThanOrEqual = 6

  /// Whether `lhs` stands in this relation to `rhs`; `.none` holds of anything.
  public func holds<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
    switch self {
    case .none: true
    case .equality: lhs == rhs
    case .inequality: lhs != rhs
    case .greaterThan: lhs > rhs
    case .greaterThanOrEqual: lhs >= rhs
    case .lessThan: lhs < rhs
    case .lessThanOrEqual: lhs <= rhs
    }
  }
}
