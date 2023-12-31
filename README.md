SwiftOCA
--------

SwiftOCA is pure Swift implementation of the [AES70/OCA](https://ocaalliance.com/what-is-aes70/) control protocol, principally used for remote control of professional audio devices.

The package consists of three libraries:

* [SwiftOCA](Sources/SwiftOCA): an OCA controller (client)
* [SwiftOCAUI](Sources/SwiftOCAUI): framework for binding SwiftUI views to OCA classes
* [SwiftOCADevice](Sources/SwiftOCADevice): an OCA device (server)

All APIs use `async/await` and support both macOS and Linux. A sample SwiftUI view library is also included, and a Flutter bridge is under development [here](https://github.com/PADL/FlutterSwiftOCA). Examples can be found in [Examples](Examples).

The libraries should be considered a work in progress: they are sufficient for the author's intended use cases, but not all classes and properties are yet implemented, nor is there currently support for WebSockets. Pull requests to implement these features are welcome.

Below is a screenshot generated using `SwiftOCAUI` controls:

![OCABrowser](Documentation/OCABrowser.png)

--
Luke Howard <lukeh@lukktone.com>

