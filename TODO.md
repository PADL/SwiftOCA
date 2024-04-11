SwiftOCA
--------

- implement (decent) control views for common controls
- WebSocket client-side support
- fix class version logic
- tests
- SwiftOCA/OCC/ControlClasses/Root.swift:159:39:
    `warning: capture of 'propertyKeyPath' with non-sendable type 'PartialKeyPath<OcaRoot>' in a `@Sendable` closure`
- SwiftOCA/OCP.1/Ocp1ConnectionMonitor.swift:145:23:
    `warning: passing argument of non-sendable type 'inout ThrowingTaskGroup<Void, any Error>' outside of actor-isolated context may introduce data races`

SwiftOCADevice
--------------

- disjoint namespace support for remote object proxies
