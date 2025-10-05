SwiftOCA
--------

SwiftOCA is pure Swift implementation of the [AES70](https://ocaalliance.com/what-is-aes70/) control protocol, principally used for remote control of professional audio devices.

The package consists of three libraries:

* [SwiftOCA](Sources/SwiftOCA): an OCA controller (client)
* [SwiftOCAUI](Sources/SwiftOCAUI): framework for binding SwiftUI views to OCA classes
* [SwiftOCADevice](Sources/SwiftOCADevice): an OCA device (server)

All APIs are async-safe and support both macOS and Linux: on macOS, [FlyingFox](https://github.com/swhitty/FlyingFox) is used for socket I/O, and on Linux, [IORingSwift](https://github.com/PADL/IORingSwift).

| Platform | TCP | UDP client | UDP server | WS client | WS server | Local |
| -:       | :-  | :-         | :-         | :-        | :-        | :-    |
| macOS    | ✅  | ✅         | ✅         | ❌        | ✅        | ✅    |
| Linux    | ✅  | ✅         | ✅         | ❌        | ❌        | ✅    |

Sample code can be found in [Examples](Examples).

[ocacli](https://github.com/PADL/ocacli) is a command-line OCA controller that is implemented using SwiftOCA. SwiftOCA is also compatible with third-party OCA controllers such as [AES70Explorer](https://aes70explorer.com).

A sample SwiftUI view library is also included, and a Flutter bridge is under development [here](https://github.com/PADL/FlutterSwiftOCA). Below is a screenshot generated using `SwiftOCAUI` controls:

![OCABrowser](Documentation/OCABrowser.png)

Example use to walk device tree:

```swift
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import SwiftOCA

let connection = try await Ocp1TCPConnection(deviceAddress: makeLoopbackAddress())
try await connection.connect()

// walk the device tree recursively, returning any object that can be contained
// and printing its role path
for actionObject in try await connection.rootBlock.resolveActionObjectsRecursive()
  .compactMap({ $0.memberObject as? OcaOwnable }) {
  try? await print("- \(actionObject.rolePathString)")
}

try? await connection.disconnect()

func makeLoopbackAddress() -> Data {
  var address = sockaddr_in()

  #if canImport(Darwin)
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(65000).bigEndian
  address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

  return withUnsafeBytes(of: &address) { Data(
    bytes: $0.baseAddress!,
    count: $0.count
  ) }
}
```

Luke Howard <lukeh@lukktone.com>
