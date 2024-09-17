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
SwiftOCA/OCP.1/Backend/Ocp1CFSocketConnection.swift:429:32: warning: passing argument of non-sendable type 'inout AnyAsyncIterator<CFSocket.Message>' (aka 'inout AnyAsyncIterator<(any SocketAddress, Data)>') outside of global actor 'OcaConnection'-isolated context may introduce data races
SwiftOCADevice/OCP.1/Backend/FlyingSocks/Ocp1FlyingFoxController.swift:64:41: warning: type 'AnyAsyncSequence<(any Ocp1Message, Bool)>' does not conform to the 'Sendable' protocol
SwiftOCADevice/OCP.1/Backend/FlyingSocks/Ocp1FlyingFoxDeviceEndpoint.swift:123:13: warning: passing argument of non-sendable type 'any SocketAddress' into actor-isolated context may introduce data races
SwiftOCADevice/OCP.1/Backend/FlyingSocks/Ocp1FlyingSocksDeviceEndpoint.swift:173:23: warning: passing argument of non-sendable type 'inout ThrowingTaskGroup<Void, any Error>' outside of global actor 'OcaDevice'-isolated context may introduce data races
```

Warnings
--------

```
SwiftOCA/OCC/ControlClasses/Root.swift:162:40: warning: conditional cast from '[String : Any]' to '[String : any Sendable]' always succeeds
SwiftOCA/OCC/ControlClasses/Root.swift:185:1: warning: extension declares a conformance of imported type 'PartialKeyPath' to imported protocol 'Sendable'; this will not behave correctly if the owners of 'Swift' introduce this conformance in the future
SwiftOCA/OCP.1/ReflectionMirror/ReflectionMirror.swift:14:1: warning: using '@_implementationOnly' without enabling library evolution for 'SwiftOCA' may lead to instability during execution
```
