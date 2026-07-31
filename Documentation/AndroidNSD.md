# Android NSD support for `OcaConnectionBroker`

Design notes for giving `ConnectionBroker.swift`'s `BrowserMonitor` a path on
Android, backed by `android.net.nsd.NsdManager`.

## Current state

`Sources/SwiftOCA/OCA/Browsing/ConnectionBroker.swift:17` opens with

```swift
#if canImport(Darwin) || canImport(dnssd)
```

and that guard closes at the end of the file, so on Android the connection
broker does not exist at all — not merely the browser. Inside it,
`BrowserMonitor.init` (`:269`) selects an implementation:

| Platform | Implementation | Backing API |
| --- | --- | --- |
| Darwin | `OcaNetServiceBrowser` | `NetServiceBrowser` |
| Linux | `OcaDNSServiceBrowser` | `dns_sd.h` |
| everything else | `throw Ocp1Error.notImplemented` | — |

Two protocols must be satisfied, both in
`Sources/SwiftOCA/OCA/Browsing/NetworkAdvertisingServiceBrowser.swift`:

- `OcaNetworkAdvertisingServiceBrowser` (`:296`) — `init(serviceType:) throws`,
  `browseResults: AsyncStream<…>`, `start() async throws`, `stop() throws`
- `OcaNetworkAdvertisingServiceInfo` (`:65`) — `service`, `serviceType`, `name`,
  `domain`, throwing `hostname` / `port` / `addresses` / `txtRecords`, and
  `resolve() async throws`

`OcaDNSServiceBrowser` is the closer structural model of the two, since like NSD
it is callback-driven with a separate resolve step.

## Layer 1 — wrapping NSD in Swift

swift-java cannot implement a Java *interface* directly from Swift, and every
interesting part of NSD is delivered through listener interfaces. FlutterSwift
already solves exactly this shape, and its approach transfers directly.

The pattern (see `FlutterSwift/Sources/FlutterAndroid`):

1. A Java class extends `SwiftHeapObjectHolder` — which holds a `long` pointer to
   a Swift heap object, retains it on construction via a `static native`, and
   releases it through a `java.lang.ref.Cleaner`.
2. That class implements the Java interface, declaring each interface method
   `native`.
3. Swift supplies the bodies via `@JavaImplementation("fully.qualified.Name")`
   plus `@JavaMethod`, recovering the Swift object from the held pointer.

`FlutterSwiftBinaryMessageHandler.java` is the reference: 7 lines of Java for a
one-method interface, with `_FlutterSwiftBinaryMessageHandlerNativeMethods.swift`
on the other side.

For NSD we need two such shims:

- `OcaNsdDiscoveryListener implements NsdManager.DiscoveryListener`
  — `onDiscoveryStarted`, `onDiscoveryStopped`, `onServiceFound`,
  `onServiceLost`, `onStartDiscoveryFailed`, `onStopDiscoveryFailed`
- `OcaNsdResolveListener implements NsdManager.ResolveListener`
  — `onServiceResolved`, `onResolveFailed`

plus a `swift-java.config` importing `android.net.nsd.NsdManager`,
`android.net.nsd.NsdServiceInfo`, `java.net.InetAddress` and the two shims. Its
`classpath` must point at the platform `android.jar`
(`$ANDROID_HOME/platforms/android-36/android.jar`); FlutterSwift's config
hardcodes a path to `flutter.jar`, which is worth improving on rather than
copying.

### Manifest gating: an environment variable, not `#if os(Android)` — and not a trait

`Package.swift`'s `#if os(…)` is evaluated on the **build host**, not the target.
Android builds here are cross-compiled from macOS, so `#if os(Android)` in the
manifest is never true.

A trait looks like the idiomatic fit, and SwiftPM genuinely does prune
trait-disabled package dependencies — but it cannot work here.
`Target.PluginUsage.plugin(name:package:)` takes no `condition:`, so the
swift-java plugin usage is unconditional; pruning swift-java via a trait leaves
that plugin product dangling and every non-Android build fails with
`product 'JavaCompilerPlugin' … not found in package 'swift-java'`. Note that
`swift package resolve` still *succeeds* in that state — only `build` fails, so
resolve is not a sufficient check.

So gating is on `SWIFTOCA_ANDROID_NSD`, set by the Android gradle build, matching
FlutterSwift's `FLUTTER_SWIFT_JVM` convention. Moving this target into its own
package would let a trait do the whole job, since the plugin usage would then
live in a package that is pruned wholesale.

## Layer 2 — where the `Context` comes from

This is the one genuinely unresolved design question, and it should be settled
before any code is written.

`NsdManager` is only reachable via `context.getSystemService(Context.NSD_SERVICE)`.
SwiftOCA is a library with no `Context`, and
`init(serviceType:) throws` leaves nowhere to pass one.

| Option | Assessment |
| --- | --- |
| **(a) Process-global registration** — `OcaAndroidNsd.configure(context:)` called once at startup | Recommended. No protocol churn. Fits the app as it already stands: `MainActivity` is a `FlutterActivity` (hence a `Context`) and already constructs `Runner`, so it can hand one over. Pass `applicationContext`, **not** the Activity — Android restarts the Activity, which is why `InfernoUIRunner` already uses `shared()` rather than a fresh runner. |
| (b) Widen the browser protocol with a configuration/environment parameter | Invasive; forces churn on the Darwin and Linux implementations for a need only one platform has. |
| (c) Reflection via `ActivityThread.currentApplication()` | No plumbing, but greylisted and fragile. |

## Layer 3 — the adapter

`OcaNsdServiceBrowser` + a private `_NsdServiceInfo`, mirroring
`OcaDNSServiceBrowser`'s structure: a `Mutex<Set<String>>` of discovered service
IDs for add/remove deduplication, an `AsyncStream` continuation for
`browseResults`, `start()` calling `discoverServices(type, PROTOCOL_DNS_SD,
listener)` and `stop()` calling `stopServiceDiscovery(listener)` before
finishing the continuation.

The substance is in the impedance mismatches, all of which are load-bearing:

1. **Service type strings must round-trip exactly.** The enum rawValues carry a
   trailing dot (`"_oca._tcp."`, `NetworkApplicationDataTypes.swift:44`) but
   Android wants `"_oca._tcp"`. Worse, `NsdServiceInfo.getServiceType()` is
   inconsistent across API levels about leading/trailing dots and sometimes
   appends `.local.`. Since `id` is `"\(name).\(serviceType.rawValue)\(domain)"`
   and that string *is* the broker's device identity, a normalization slip means
   `.removed` never matches an earlier `.added` and stale devices accumulate
   forever. Normalize on both edges and test it directly.
2. **Domain.** Android never exposes one. Synthesize `"local."` so `id` matches
   what the Darwin and dnssd browsers produce for the same device.
3. **Resolve must be serialized.** The legacy `resolveService()` permits exactly
   one in-flight resolve per `NsdManager`; concurrent calls fail with
   `FAILURE_ALREADY_ACTIVE`. This is a long-standing Android defect, and the
   broker resolves every discovered service — so with more than one OCA device on
   the network it *will* fire. Either serialize resolves through an actor with
   retry, or use `registerServiceInfoCallback` (API 34+). inferno_ui is
   `minSdk = 24` / `targetSdk = 36`, so API 34 is usable but needs a runtime
   version check with the serialized legacy path as fallback.
4. **Addresses need synthesized sockaddrs.** The protocol's `addresses: [Data]`
   is consumed by `socketAddresses` via `AnySocketAddress(bytes:)`, i.e. it
   expects `sockaddr` bytes. Android hands back `InetAddress`, which is a bare IP
   with no family or port. A `sockaddr_in` / `sockaddr_in6` must be constructed,
   port included. The Darwin and dnssd paths get real sockaddrs for free, so this
   has no precedent to copy in-tree.
5. **TXT records.** `getAttributes()` is `Map<String, byte[]>`; decode as UTF-8
   into `[String: String]`, tolerating attributes that are present but valueless.
6. **Threading is fine, lifetime is the risk.** NSD callbacks arrive on binder
   threads, which are Java threads and therefore JNI-attached, and
   `AsyncStream.Continuation.yield` is thread-safe. What matters is that the
   Swift listener object outlives discovery — which is precisely what
   `SwiftHeapObjectHolder`'s retain plus `Cleaner` provides.
7. **Permissions.** `android/app/src/main/AndroidManifest.xml` currently declares
   *none*. Flutter injects `INTERNET` into debug and profile manifests only, so
   release builds need it declared explicitly. Apps targeting API 33+ that
   discover services with `NsdManager` also need `NEARBY_WIFI_DEVICES` — verify
   against the target API before assuming discovery works on a real device.

## Layer 4 — wiring it in

Two edits, both trivial once the above exists:

- widen the file guard at `ConnectionBroker.swift:17`
- add the `#elseif` arm in `BrowserMonitor.init` at `:269`

## Suggested order

1. Settle the `Context` question (Layer 2) — everything else depends on it.
2. Stand up the `AndroidNetworkServiceDiscovery` target, env-var gate, and `swift-java.config` with a
   single trivial binding, and get it compiling in the cross-build. The build
   plumbing is where the time will go, not the logic.
3. Add the discovery listener shim and `OcaNsdServiceBrowser` with `resolve()`
   stubbed, and confirm `.added` / `.removed` round-trip against a real device.
4. Add resolve, addresses, and TXT records.
5. Wire into `BrowserMonitor` and delete the `notImplemented` arm for Android.
