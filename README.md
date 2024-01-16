SwiftOCA
--------

SwiftOCA is pure Swift implementation of the [AES70/OCA](https://ocaalliance.com/what-is-aes70/) control protocol, principally used for remote control of professional audio devices.

The package consists of three libraries:

* [SwiftOCA](Sources/SwiftOCA): an OCA controller (client)
* [SwiftOCAUI](Sources/SwiftOCAUI): framework for binding SwiftUI views to OCA classes
* [SwiftOCADevice](Sources/SwiftOCADevice): an OCA device (server)

All APIs use `async/await` and support both macOS and Linux: on macOS, [FlyingFox](https://github.com/swhitty/FlyingFox) is used for socket I/O, and on Linux, [IORingSwift](https://github.com/PADL/IORingSwift).

| Platform | TCP | UDP client | UDP server | WS client | WS server | Local |
| -:       | :-  | :-         | :-         | :-        | :-        | :-    |
| macOS    | ✅  | ✅         | ❌         | ❌        | ✅        | ✅    |
| Linux    | ✅  | ✅         | ✅         | ❌        | ❌        | ✅    |

Example code can be found in [Examples](Examples).

In the absence of a UML/XMI to Swift parser (left as a future task), not all AES70 classes are implemented, but adding a new one is trivial using the `@OcaProperty` and `@OcaDeviceProperty` wrappers. For a class with only properties, it is only necessary to declare the property and accessor IDs, and all logic including event notification will be handled at runtime. For custom logic, override the `handleCommand(from:)` method. Custom access control can be implemented at the object or device level by overriding `ensureReadable(by:command)` and `ensureWritable(by:command)`.

Serialization to JSON types is provided using the `jsonObject` and `deserialize(jsonObject:)` methods, which walk the list of declared properties, encoding non-JSON types using Codable. 

A sample SwiftUI view library is also included, and a Flutter bridge is under development [here](https://github.com/PADL/FlutterSwiftOCA). Below is a screenshot generated using `SwiftOCAUI` controls:

![OCABrowser](Documentation/OCABrowser.png)

--
Luke Howard <lukeh@lukktone.com>

