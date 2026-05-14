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

/// Sync, thread-safe lookup interface for TLS pre-shared keys. The OpenSSL
/// PSK callback fires inside `SSL_do_handshake` and can't `await`, so the
/// engine queries the provider directly; holding a reference (rather than
/// snapshotting) lets later store updates take effect on the next handshake
/// without copying secrets out of canonical storage.
public protocol OcaPreSharedKeyProvider: Sendable {
  /// Synchronously look up the PSK for `identity` and pass it to `body`.
  /// Returns `nil` (without invoking `body`) if no key is registered.
  /// Implementations MUST keep the buffer valid only for the call, and MUST
  /// be safe to call concurrently.
  func withPreSharedKey<T>(
    forIdentity identity: String,
    _ body: (UnsafeBufferPointer<UInt8>) throws -> T
  ) rethrows -> T?
}
