//
// Copyright (c) 2023 PADL Software Pty Ltd
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
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif
import SocketAddress

public func deviceAddressToString(_ deviceAddress: Data) -> String {
  deviceAddress.withUnsafeBytes {
    $0.withMemoryRebound(to: sockaddr.self) {
      deviceAddressToString($0.baseAddress!)
    }
  }
}

public func deviceAddressToString(
  _ deviceAddress: UnsafePointer<sockaddr>,
  includePort: Bool = true
) -> String {
  deviceAddressToString(deviceAddress.pointee, includePort: includePort)
}

package func deviceAddressToString(
  _ deviceAddress: any SocketAddress,
  includePort: Bool = true
) -> String {
  guard let presentationAddress = try? deviceAddress.presentationAddress else {
    return ""
  }

  if !includePort &&
    (
      deviceAddress.family == sa_family_t(AF_INET) || deviceAddress
        .family == sa_family_t(AF_INET6)
    )
  {
    let lastDelimiterIndex = presentationAddress.lastIndex(of: ":")!
    let endIndex = presentationAddress.index(before: lastDelimiterIndex)
    return String(presentationAddress[...endIndex])
  } else {
    return presentationAddress
  }
}
