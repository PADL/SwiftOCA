//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

#if canImport(WinSDK)
import WinSDK

// These two have no usable WinSDK symbol to collide with (Winsock has no
// `AF_LOCAL`; ucrt's `errno` is an unimportable macro), so they are exposed at
// `package` scope and shared by the other targets in this package (e.g.
// SwiftOCADevice) rather than each redeclaring them.

// Winsock spells the local/Unix-domain family `AF_UNIX`; there is no `AF_LOCAL`.
package let AF_LOCAL = AF_UNIX

// ucrt's `errno` is a macro (`(*_errno())`) that can't be imported into Swift,
// and the socket routines used here surface failures via the Winsock error
// code anyway.
package var errno: Int32 { WSAGetLastError() }

// Winsock socket error codes that have no entry in ucrt's <errno.h>.
package let ESHUTDOWN = Int32(WSAESHUTDOWN)

// IPPROTO_* import as an `IPPROTO` enum on Windows rather than integers.
package let IPPROTO_TCP = CInt(WinSDK.IPPROTO_TCP.rawValue)
package let IPPROTO_IPV6 = CInt(WinSDK.IPPROTO_IPV6.rawValue)
#endif
