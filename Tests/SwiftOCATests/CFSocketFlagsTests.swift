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

#if canImport(CoreFoundation) && NonEmbeddedBuild

import CoreFoundation
import Foundation
@testable import SwiftOCA
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#endif

/// The `CFSocket` fcntl helpers: `O_NONBLOCK` set means non-blocking, and
/// `set(flags:mask:)` must honour its `flags` argument rather than always setting `mask`.
@Suite struct CFSocketFlagsTests {
  private static func withSocket(_ body: (CFSocket, CInt) throws -> ()) throws {
    var fds: [CInt] = [-1, -1]
    try #require(socketpair(AF_UNIX, SwiftOCA.SOCK_STREAM, 0, &fds) == 0)
    defer {
      close(fds[0])
      close(fds[1])
    }
    let socket = try #require(CFSocketCreateWithNative(nil, fds[0], 0, nil, nil))
    defer { CFSocketInvalidate(socket) }
    try body(socket, fds[0])
  }

  private static func nonBlockingBit(_ fd: CInt) -> Bool {
    fcntl(fd, F_GETFL, 0) & O_NONBLOCK != 0
  }

  @Test func setBlockingRoundTrips() throws {
    try Self.withSocket { socket, fd in
      try socket.setBlocking(false)
      #expect(Self.nonBlockingBit(fd))
      #expect(try socket.isBlocking == false)

      try socket.setBlocking(true)
      #expect(!Self.nonBlockingBit(fd))
      #expect(try socket.isBlocking == true)
    }
  }

  @Test func setFlagsClearsBitsOutsideFlagsWithinMask() throws {
    try Self.withSocket { socket, fd in
      try socket.set(flag: O_NONBLOCK, to: true)
      #expect(Self.nonBlockingBit(fd))
      try socket.set(flags: 0, mask: O_NONBLOCK)
      #expect(!Self.nonBlockingBit(fd))
    }
  }
}

#endif
