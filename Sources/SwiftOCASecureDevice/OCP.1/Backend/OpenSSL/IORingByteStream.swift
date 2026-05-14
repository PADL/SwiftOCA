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

#if canImport(COpenSSL) && canImport(IORing)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import IORing
internal import IORingUtils

/// `Ocp1ByteStream` adapter for an `IORing.Socket`. The fd closes when the
/// wrapping struct is released, so `close()` is a no-op.
struct IORingByteStream: Ocp1ByteStream {
  let socket: Socket

  func read(count: Int, awaitingAllRead: Bool) async throws -> Data {
    try await Data(socket.read(count: count, awaitingAllRead: awaitingAllRead))
  }

  func write(_ data: Data) async throws {
    _ = try await socket.write(Array(data), count: data.count, awaitingAllWritten: true)
  }

  func close() async {}
}

#endif
