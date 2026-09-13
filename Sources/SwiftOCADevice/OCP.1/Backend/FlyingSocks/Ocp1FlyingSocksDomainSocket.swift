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

#if os(macOS) || os(iOS) || os(Windows) || !NonEmbeddedBuild || canImport(FlyingFox)

import SystemPackage
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif

/// Removes the socket file at `path`, if there is one: before binding, one left behind by
/// an earlier endpoint, which would make bind fail; after closing, the endpoint's own.
/// Anything else at `path`, such as a regular file named by mistake, is kept, and bind
/// reports the path as in use.
package func unlinkSocketFile(at path: String) throws {
  #if !canImport(WinSDK)
  var st = stat()
  guard lstat(path, &st) == 0 else {
    if errno == ENOENT { return }
    throw Errno(rawValue: errno)
  }
  guard st.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else { return }
  #endif
  if unlink(path) < 0, errno != ENOENT {
    throw Errno(rawValue: errno)
  }
}

#endif
