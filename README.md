SwiftOCA
--------

SwiftOCA is pure Swift implementation of the AES70/OCA control protocol, principally used for remote control of professional audio devices. The package consists of two libraries:

* [SwiftOCA](Sources/SwiftOCA): an OCA controller (client)
* [SwiftOCADevice](Sources/SwiftOCADevice): an OCA device (server)

All APIs use `async/await` and support both macOS and Linux. A sample SwiftUI view library is also included, and a Flutter bridge is under development [here](https://github.com/PADL/FlutterSwiftOCA). Examples can be found in [Examples](Examples).

![OCABrowser](Documentation/OCABrowser.png)

The libraries should be considered a work in progress: they are sufficient for the author's intended use cases, but not all classes and properties are yet implemented, nor is there currently support for WebSockets. Pull requests to implement these features are welcome.

Luke Howard <lukeh@lukktone.com>
July 2023

