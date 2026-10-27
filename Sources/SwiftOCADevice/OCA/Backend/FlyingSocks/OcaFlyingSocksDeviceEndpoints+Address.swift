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

// The FlyingSocks endpoints' `address`, apart from their files: FlyingSocks has a
// `SocketAddress` of its own, and this file imports only the SocketAddress package's.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif
import SocketAddress

#if canImport(FlyingFox)
public extension OcaFlyingFoxDeviceEndpoint {
  nonisolated var address: any SocketAddress {
    storage
  }
}
#endif

#if os(macOS) || os(iOS) || os(Windows) || !NonEmbeddedBuild
public extension OcaFlyingSocksStreamDeviceEndpoint {
  nonisolated var address: any SocketAddress {
    addressStorage
  }
}
#endif

#if os(macOS) || os(iOS) || !NonEmbeddedBuild
public extension OcaFlyingSocksDatagramDeviceEndpoint {
  nonisolated var address: any SocketAddress {
    addressStorage
  }
}
#endif
