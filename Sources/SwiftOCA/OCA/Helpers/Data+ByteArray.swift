//
// Copyright (c) 2026 PADL Software Pty Ltd
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

package extension Data {
  /// The bytes as an array, for a socket API that takes one. `[UInt8](data)` copies
  /// them and then makes an iterator it discards, which costs more than the copy:
  /// every PDU sent over io_uring comes through here.
  var byteArray: [UInt8] {
    withUnsafeBytes { [UInt8]($0) }
  }
}
