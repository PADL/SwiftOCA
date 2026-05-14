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
import SwiftOCA
import SwiftOCADevice
import SwiftOCASecure

/// Bridges `OcaSecurityManager`'s PSK store to the TLS engine. Lives in
/// `SwiftOCASecureDevice` so `SwiftOCADevice` doesn't depend on TLS.
extension SwiftOCADevice.OcaSecurityManager: OcaPreSharedKeyProvider {
  public nonisolated func withPreSharedKey<T>(
    forIdentity identity: String,
    _ body: (UnsafeBufferPointer<UInt8>) throws -> T
  ) rethrows -> T? {
    // Copy the PSK bytes into a fresh non-COW heap buffer while holding
    // the lock, then drop the lock and invoke `body` against that buffer.
    // Two reasons for the extra copy:
    //   1. No parallel `Data` reference escapes the lock, so `_add` /
    //      `_delete` always see refcount=1 when they wipe and can clear
    //      the stored bytes deterministically — Swift `Data`'s COW would
    //      otherwise redirect the wipe to a temporary copy.
    //   2. The local buffer is uniquely owned, so we can OPENSSL_cleanse-
    //      equivalent wipe it before deallocation, bounding plaintext PSK
    //      lifetime to the handshake that requested it.
    let copy: UnsafeMutableBufferPointer<UInt8>? = _preSharedKeys.withLock { dict in
      guard let data = dict[identity] else { return nil }
      let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: data.count)
      data.withUnsafeBytes { src in
        if let base = src.bindMemory(to: UInt8.self).baseAddress,
           let dst = buf.baseAddress {
          dst.update(from: base, count: data.count)
        }
      }
      return buf
    }
    guard let copy else { return nil }
    defer {
      UnsafeMutableRawBufferPointer(copy).initializeMemory(as: UInt8.self, repeating: 0)
      copy.deallocate()
    }
    return try body(UnsafeBufferPointer(copy))
  }

  /// Configured PSK identities — used for the Bonjour
  /// `securityKeyIdentities` advertisement.
  public nonisolated var preSharedKeyIdentities: [OcaString] {
    _preSharedKeys.withLock { Array($0.keys) }
  }
}
