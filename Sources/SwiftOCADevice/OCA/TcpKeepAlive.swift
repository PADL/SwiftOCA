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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif
import SwiftOCA

/// TCP keepalive for accepted stream sockets: probes start after `idle`, repeat every
/// `interval` up to `count` times, so a dead peer is gone 120 s after its last traffic. On
/// Linux `TCP_USER_TIMEOUT` is set to the same, so unacknowledged writes fail then too.
package enum OcaTcpKeepAlive {
  package static let idle = Duration.seconds(60)
  package static let interval = Duration.seconds(10)
  package static let count = 6
  package static let userTimeout = idle + interval * count

  /// The options to set, as `setsockopt` takes them.
  package static var socketOptions: [(level: CInt, name: CInt, value: CInt)] {
    var options: [(level: CInt, name: CInt, value: CInt)] = [(CInt(SOL_SOCKET), CInt(SO_KEEPALIVE), 1)]
    #if canImport(Darwin)
    options += [
      (CInt(IPPROTO_TCP), TCP_KEEPALIVE, CInt(idle.components.seconds)),
      (CInt(IPPROTO_TCP), TCP_KEEPINTVL, CInt(interval.components.seconds)),
      (CInt(IPPROTO_TCP), TCP_KEEPCNT, CInt(count)),
    ]
    #elseif canImport(Glibc) || canImport(Musl) || canImport(Android)
    options += [
      (CInt(IPPROTO_TCP), TCP_KEEPIDLE, CInt(idle.components.seconds)),
      (CInt(IPPROTO_TCP), TCP_KEEPINTVL, CInt(interval.components.seconds)),
      (CInt(IPPROTO_TCP), TCP_KEEPCNT, CInt(count)),
      (CInt(IPPROTO_TCP), TCP_USER_TIMEOUT, CInt(userTimeout.components.seconds * 1000)),
    ]
    #elseif canImport(WinSDK)
    // Windows 10 1709 and later take these in seconds; without them Winsock probes after 2 h
    options += [
      (CInt(IPPROTO_TCP), TCP_KEEPIDLE, CInt(idle.components.seconds)),
      (CInt(IPPROTO_TCP), TCP_KEEPINTVL, CInt(interval.components.seconds)),
      (CInt(IPPROTO_TCP), TCP_KEEPCNT, CInt(count)),
    ]
    #endif
    return options
  }

  /// Sets every option through `set`, a backend's `setsockopt`.
  package static func apply(
    _ set: (_ level: CInt, _ name: CInt, _ value: CInt) throws -> ()
  ) rethrows {
    for option in socketOptions {
      try set(option.level, option.name, option.value)
    }
  }
}
