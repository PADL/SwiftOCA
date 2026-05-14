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

/// Stream-oriented transport the OpenSSL engine pumps `read`/`write` through.
/// DTLS keeps its own UDP-aware abstraction — this one is TCP-like only.
protocol Ocp1ByteStream: Sendable {
  /// Read up to `count` bytes (or exactly `count` when `awaitingAllRead`).
  /// Throws `Ocp1Error.notConnected` on EOF.
  func read(count: Int, awaitingAllRead: Bool) async throws -> Data

  /// Write all of `data`; throw on partial write or peer reset.
  func write(_ data: Data) async throws

  /// Idempotent close. Subsequent reads should throw `.notConnected`.
  func close() async
}
