SwiftOCA
--------

- implement (decent) control views for common controls
- WebSocket client-side support
- fix class version logic
- tests
- check bugs in FlyingSocks client

SwiftOCADevice
--------------

- disjoint namespace support for remote object proxies

Concurrency issues
------------------

```
SwiftOCA/OCP.1/Ocp1ConnectionMonitor.swift:143:23: warning: passing argument of non-sendable type 'inout ThrowingTaskGroup<Void, any Error>' outside of global actor 'OcaConnection'-isolated context may introduce data races
SwiftOCADevice/OCP.1/Backend/FlyingSocks/Ocp1FlyingFoxController.swift:64:41: warning: type 'AnyAsyncSequence<(any Ocp1Message, Bool)>' does not conform to the 'Sendable' protocol
SwiftOCADevice/OCP.1/Backend/FlyingSocks/Ocp1FlyingFoxDeviceEndpoint.swift:123:13: warning: passing argument of non-sendable type 'any SocketAddress' into actor-isolated context may introduce data races
SwiftOCADevice/OCP.1/Backend/FlyingSocks/Ocp1FlyingSocksDeviceEndpoint.swift:173:23: warning: passing argument of non-sendable type 'inout ThrowingTaskGroup<Void, any Error>' outside of global actor 'OcaDevice'-isolated context may introduce data races
```
