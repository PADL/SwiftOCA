# OCP.2 (AES70-4) support

SwiftOCA speaks both AES70 control protocols:

- **OCP.1** (AES70-3): binary PDUs with positional parameters. The default.
- **OCP.2** (AES70-4): newline-delimited JSON PDUs with named parameters.

Both carry the same message model (`Ocp1Command`, `Ocp1Response`,
`Ocp1Notification2`, keep-alives) over the same transports; the protocol is a
per-connection or per-endpoint option, not a separate class hierarchy. OCP.2 is
available in non-embedded builds only (it uses Foundation's JSON).

## Selecting the protocol

Controller:

```swift
let options = Ocp1ConnectionOptions(controlProtocol: .ocp2)
let connection = try Ocp1TCPConnection(deviceAddress: address, options: options)
// or
let ws = Ocp1FlyingFoxConnection(host: "device.local", port: 50001, options: options)
```

Device:

```swift
let tcp = try await Ocp1FlyingSocksStreamDeviceEndpoint(
  address: address, device: device, controlProtocol: .ocp2)
let ws = try await Ocp1FlyingFoxDeviceEndpoint(
  address: address, device: device, controlProtocol: .ocp2, path: "/aes70")
```

`OcaConnectionBroker` browses the OCP.2 service types (`_ocajson._tcp`,
`_ocajsonws._tcp`) alongside the OCP.1 ones and picks the protocol from the
service type; an OCP.2 endpoint advertises itself under the JSON service type
and, for WebSocket, the `path` TXT record.

Transports in this release: TCP, UDP, WebSocket, and the in-process local loopback.
TLS-PSK (`_ocajsonsec._tcp`) is not yet wired up; the `DeviceReset` PDU is decoded
and logged but not acted on.

UDP is a Control Session Transport Type in its own right (AES70-4 10.4.3), served
by passing `controlProtocol: .ocp2` to a datagram endpoint and advertised as
`_ocajson._udp`. A session opens on the controller's first keep-alive and the
device ignores anything sent before it, as the standard requires; `connect()`
sends one for datagram transports. Note that a PDU must fit a datagram, and JSON
is bulkier than OCP.1 binary for the same message.

## Framing and marshaling

`Ocp2WireFormat` frames one JSON object per line (AES70-4 6.3) and validates
the envelope strictly: `ProtocolVersion` must be 1, exactly one payload member
is allowed, and a command with a missing or spurious member is rejected (the
standard's malformed examples X01–X03). WebSocket connections use the
`AES70-OCP.2` subprotocol and text frames; a binary frame closes the socket
with 1003 and a malformed message with 1007.

`Ocp2Encoder` / `Ocp2Decoder` marshal OCA values per AES70-4 clause 8: blobs
as base64, maps as arrays of `[key, value]` pairs, class IDs as arrays with a
nonstandard authority as `[65535, "FA2AE9"]`, property/method/event IDs as
`[DefLevel, Index]`, enumerations as numbers (names are accepted on receipt),
composite datatypes as objects keyed by field name. Non-finite floats use the
`"Infinity"` / `"-Infinity"` / `"NaN"` spellings.

The controller-side JSON export (`OcaRoot.jsonObject`,
`OcaProperty.getJsonValue`) is this same representation: each property under
its OCP.2 wire name with its AES70-4 value, plus `ONo`, `ClassID`,
`ClassVersion`. A bounded property
takes the shape of its getter response (`Gain`, `MinGain`, `MaxGain`). The
device-side dataset/patch serialisation is unchanged.

## Parameter names

OCP.2 keys method parameters by their AES70-2A names. SwiftOCA derives them
from Swift identifiers rather than carrying a copy of the model:

1. **Property accessors** are named after the Swift property, first letter
   upper-cased (`gain` → `Gain`; a bounded property's getter returns `Gain`,
   `MinGain`, `MaxGain`). Where the model's spelling differs, pass `ocp2Name:`
   to the property wrapper on both sides, e.g. `OcaDeviceManager`'s
   `deviceName` is the model's `Name`.
2. **Parameter records** (`Ocp1ParametersReflectable` structs) use their field
   names, upper-cased; an explicit `CodingKeys` enum forces a spelling.
3. **Hand-written methods** name single parameters explicitly:
   `encodeResponse(value, name: "Result")` on the device,
   `sendCommandRrq(methodID:parameters:parameterNames:)` on the controller.
   An unnamed scalar goes out as `"Value"`.

Receiving is lenient whatever the sender spells: names match
case-insensitively, a single-parameter object is accepted under any member
name, enumerations may be names or numbers, and an integer may arrive as a
string (as in the standard's own examples).

OCA 1.5B makes every method and event argument UpperCamelCase, getter
out-parameters included (`MinGain`, `Lockable`, `MemberONo`), and that is what
SwiftOCA sends; the 2023 model's lower-case spellings (`lockable`, `delayTime`)
still match on receipt. Derived names can differ from the model by more than
case for a minority of accessors. The `Ocp2NamingOracleTests` test lists them:
point `AES70_2_XMI` at the AES70-2 UML export (`AES70-2-2023-231218.xmi`) and
run

```
AES70_2_XMI=/path/to/AES70-2-2023-231218.xmi swift test --filter Ocp2NamingOracleTests
```

and add `ocp2Name:` overrides where exact spelling matters for a peer.

## API notes

- `OcaControlProtocol`, `Ocp1ConnectionOptions.controlProtocol`,
  `.maximumPduSize` and `.heartbeatTime` (overrides a transport's default
  keep-alive; WebSocket OCP.1 relies on ping/pong, so set one for OCP.2 if the
  device requires keep-alives).
- `Ocp1Parameters.format` says whether `parameterData` is OCP.1 bytes or a
  serialised OCP.2 `Parameters` object; `Ocp1Parameters(ocp2ParameterData:)`
  builds the latter.
- `OcaEventParameters.encoded(as:)` encodes event data for either protocol;
  `OcaControllerDefaultSubscribing.notifySubscribers(_:parameters:)` takes it
  so each controller is notified in its own protocol. EV1 subscriptions are
  refused with `NotImplemented` on OCP.2 connections; the controller uses
  `AddSubscription2` there.
- `encodeResponse` moved from `OcaRoot` to `OcaController`, which knows the protocol
  it speaks, so a device `handleCommand` override encodes for the controller it was
  handed: `try controller.encodeResponse(value, name: "Objects")`. This is a source
  break for out-of-tree overrides — the old `OcaRoot` entry points are marked
  unavailable, and the call sites need the receiver added. Nothing is carried
  implicitly; a property accessor's OCP.2 parameter names are passed to
  `getResponse(for:names:)` rather than bound ambiently.
- The `Ocp1*` message and connection types are the protocol-neutral model;
  their names are historical.
