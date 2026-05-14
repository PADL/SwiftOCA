SwiftOCA TLS / DTLS
===================

SwiftOCA implements both OCP.1 secure transports on Apple platforms (via `Network.framework`) and Linux (via OpenSSL):

- **`ocasec/tcp`** — TLS-secured stream transport
- **`ocasec/udp`** — DTLS-secured datagram transport

The same `Ocp1TLSCredential` / `Ocp1TLSTrustRoots` types drive both backends and both transports. The public connection / endpoint types are exposed as platform-agnostic typealiases:

| Role                 | Typealias                          | Apple                              | Linux                                |
| :---                 | :---                               | :---                               | :---                                 |
| Controller (TLS)     | `Ocp1TLSStreamConnection`          | `Ocp1NWSecureTCPConnection`        | `Ocp1OpenSSLConnection`              |
| Controller (DTLS)    | `Ocp1TLSDatagramConnection`        | `Ocp1NWSecureUDPConnection`        | `Ocp1OpenSSLDTLSConnection`          |
| Device (TLS)         | `Ocp1TLSStreamDeviceEndpoint`      | `Ocp1NWSecureTCPDeviceEndpoint`    | `Ocp1OpenSSLStreamDeviceEndpoint`    |
| Device (DTLS)        | `Ocp1TLSDatagramDeviceEndpoint`    | `Ocp1NWSecureUDPDeviceEndpoint`    | `Ocp1OpenSSLDTLSDeviceEndpoint`      |

For the over-the-wire protocol, AES70-2024 §11.2.4 mandates `TLS_DHE_PSK_WITH_AES_128_CBC_SHA` over TLS 1.2 with the PSK identity hint `OCA-PSK` (exposed as `OcaPreSharedKeyIdentityHint`). SwiftOCA always advertises the AES70-mandated suite for wire-compatibility with strict AES70 peers, but offers it alongside (and prefers) modern AEAD suites — TLS 1.3 / DTLS 1.3 external PSK and TLS 1.2 DHE-PSK-AEAD — whenever the peer supports them. The exact ordering (mandated suite first vs. AEAD suites first) differs slightly between the Apple (`Network.framework`) and Linux (OpenSSL) backends; both backends honour server cipher preference, so a SwiftOCA device drives the negotiated suite regardless of which backend the controller uses.

## Credentials

`Ocp1TLSCredential` is the input both sides supply at handshake time:

```swift
public enum Ocp1TLSCredential: Sendable {
  case preSharedKey(identity: String, key: Data)
  case preSharedKeyProvider(identity: String, provider: any OcaPreSharedKeyProvider)
  case identity(SecIdentity)                            // Apple only
  case certificateFile(certPath: String, keyPath: String)
  case certificatePEM(certificate: Data, privateKey: Data)
  case pkcs12(data: Data, password: String?)
}
```

A controller passes exactly one credential to the connection initializer. A device may pass a single _server_ credential (typically a cert) and, in addition, register any number of PSKs with the device's `OcaSecurityManager` — see [Server-side PSK](#server-side-psk-via-ocasecuritymanager) below.

`.preSharedKey` is the AES70 baseline; the key bytes live in the credential value (and, on Apple, additionally in `DispatchData` that Network.framework retains). `.preSharedKeyProvider` is the keychain-friendly variant: it carries only an identity, and the TLS backend reads key bytes on demand through the provider's `withPreSharedKey(forIdentity:_:)` closure so the caller can hold the bytes in storage of its choice (mlocked memory, hardware enclave, etc.). The `.certificateFile` / `.certificatePEM` / `.pkcs12` (and Apple-only `.identity`) variants exist for deployments that prefer X.509 mutual authentication or for interop with non-AES70 TLS peers.

## Trust roots

When the peer presents a certificate, SwiftOCA verifies it against an explicit anchor set rather than the system trust store by default. Set `trustRoots:` (or `clientCertificateTrustRoots:` on the device side) to point at a private CA bundle:

```swift
public enum Ocp1TLSTrustRoots: Sendable {
  case caFile(String)
  case caData(Data)
}
```

Passing `nil` falls back to platform behaviour — `SSL_CTX_set_default_verify_paths` on Linux, `Network.framework`'s default evaluation on Apple. For PSK-only deployments, trust roots are not consulted; the shared secret authenticates the peer.

## Peer identity

Once a handshake completes, each `OcaController` exposes a `peerIdentity: OcaPeerIdentity` snapshot. Use this — not `controllerFlags.hasTransportLayerSecurity` — for any per-principal ACL decision:

```swift
public enum OcaPeerIdentity: Sendable, Hashable {
  case preSharedKey(identity: String)
  case certificate(subject: String, fingerprint: String)
  case anonymous
}
```

`.preSharedKey` carries the identity the peer sent in the TLS handshake (cleartext on the wire — never put secret material in an identity). `.certificate` carries the verified leaf's subject summary plus its lower-case-hex SHA-256 fingerprint; the fingerprint is the recommended ACL key because DN equality can be defeated by reissue against an unchanged public key. `.anonymous` covers plaintext transports and TLS connections built with `.disableCertificateVerification`; reject it for any privileged operation. `hasTransportLayerSecurity` only proves *some* trusted peer is on the wire — not which.

On Apple, PSK identities are not exposed by `sec_protocol_metadata`'s public API, so PSK handshakes there currently surface as `.anonymous` on the server side. The Linux backend captures both PSK and cert identities. Apple's TCP path additionally surfaces `.certificate(...)` for cert handshakes via the `.ready`-time TLS metadata.

## Controller (client) usage

```swift
import SwiftOCA

let credential: Ocp1TLSCredential = .preSharedKey(
  identity: OcaPreSharedKeyIdentityHint,
  key: pskBytes // 32 bytes recommended
)

let connection = try Ocp1TLSStreamConnection(
  deviceAddress: addressData,
  credential: credential,
  hostname: "device.local",         // SNI + cert hostname verification
  trustRoots: .caFile("/etc/ssl/private-ca.pem"),
  options: Ocp1ConnectionOptions(flags: [.automaticReconnect])
)

try await connection.connect()
```

`hostname:` is used for SNI on both platforms and for cert hostname verification. On Apple, supplying a hostname also overrides `NWEndpoint` to use `.name`-based resolution so the system can compare it against the cert's Subject Alternative Names; on Linux it drives `SSL_set1_host` + `SSL_set_tlsext_host_name`. With PSK credentials, `hostname:` is optional (no cert is exchanged).

### Disabling verification

For development against a self-signed cert, set `disableCertificateVerification` on `Ocp1ConnectionFlags`:

```swift
let options = Ocp1ConnectionOptions(flags: [.disableCertificateVerification])
```

This bypasses chain validation _and_ hostname verification on both platforms. Do not ship this enabled — every connect logs a `.critical` audit line so a flag accidentally copied from an example surfaces loudly.

## Device (server) usage

The device-side endpoint accepts at most one server credential, plus optional trust roots used to authenticate connecting controllers (mTLS):

```swift
import SwiftOCADevice

let endpoint = try await Ocp1TLSStreamDeviceEndpoint(
  port: 65010,
  credential: .certificateFile(
    certPath: "/etc/ssl/device.crt",
    keyPath:  "/etc/ssl/device.key"
  ),
  clientCertificateTrustRoots: .caFile("/etc/ssl/client-ca.pem")
)
try await endpoint.run()
```

The endpoint advertises `OcaControllerFlags.hasTransportLayerSecurity` and registers a Bonjour `_ocasec._tcp.` service (`OcaNetworkAdvertisingServiceType.tcpSecure`).

### Server-side PSK via `OcaSecurityManager`

`OcaSecurityManager` is the device's PSK store. Register identities during device bring-up via `loadPreSharedKey(identity:key:)`:

```swift
if let security = await device.securityManager {
  try security.loadPreSharedKey(
    identity: OcaPreSharedKeyIdentityHint,
    key: pskBytes
  )
}
let endpoint = try await Ocp1TLSStreamDeviceEndpoint(port: 65010)
try await endpoint.run()
```

The OCA `AddPreSharedKey` / `ChangePreSharedKey` / `DeletePreSharedKey` command handlers exist on `OcaSecurityManager` but the manager's `ensureWritable` currently rejects all writes with `.notImplemented` pending an admin-role authz design. PSK additions today therefore go through `loadPreSharedKey` from process code, not over the wire.

When the endpoint starts it captures the security manager as an `OcaPreSharedKeyProvider`. The Linux (OpenSSL) backend queries the provider on each handshake's PSK callback, so a `loadPreSharedKey` call after the endpoint has started takes effect on the next handshake without an endpoint restart. The Apple (Network.framework) backend snapshots the configured identities once at listener creation — additions after that point require an endpoint restart, because `NWListener` doesn't expose a way to mutate the PSK list after binding.

`OcaPreSharedKeyProvider` is also a public protocol; applications that store PSKs outside `OcaSecurityManager` can supply their own provider via the `.preSharedKeyProvider` credential or by replacing the security manager with a custom subclass.

### mTLS and PSK coexistence

`clientCertificateTrustRoots:` enables mutual TLS for certificate-based handshakes. Importantly it does _not_ preclude PSK: PSK clients are authenticated by the shared secret and bypass the `SSL_VERIFY_PEER` requirement at handshake time. The two are independent authentication paths registered against the same TLS context. A controller without a registered PSK identity must present a cert that chains to one of `clientCertificateTrustRoots`; a PSK controller is admitted without presenting a cert.

## TLS 1.3 external PSK (Linux)

On Linux, SwiftOCA wires both TLS 1.2 PSK (`SSL_CTX_set_psk_{server,client}_callback`) and TLS 1.3 external PSK (`SSL_CTX_set_psk_{find,use}_session_callback`, RFC 8446 §4.2.11) simultaneously, so the peer's preference wins:

- Linux ↔ Linux: negotiates TLS 1.3 + `TLS_CHACHA20_POLY1305_SHA256`.
- Apple ↔ Apple: negotiates TLS 1.3 + `TLS_AES_128_GCM_SHA256` (Network.framework default).
- Either side ↔ a TLS 1.2-only peer: negotiates `TLS_DHE_PSK_WITH_AES_128_CBC_SHA` (AES70 baseline).

The TLS 1.3 PSK callbacks fire only for _external_ PSKs (the prior-agreement OCA-PSK case). Session-ticket resumption flows through a different OpenSSL code path and is unaffected. SwiftOCA pins the TLS 1.3 ciphersuite list to the SHA-256 subset (`TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256`) because the synthesized PSK session is bound to the SHA-256 hash; allowing `TLS_AES_256_GCM_SHA384` would cause the PSK to be silently rejected mid-handshake.

## DTLS (datagram TLS over UDP)

The `Ocp1TLSDatagramConnection` / `Ocp1TLSDatagramDeviceEndpoint` pair carries OCP.1 over a DTLS-protected UDP flow. Construction mirrors the TLS-stream API:

```swift
import SwiftOCA

let connection = try Ocp1TLSDatagramConnection(
  deviceAddress: addressData,
  credential: .preSharedKey(identity: OcaPreSharedKeyIdentityHint, key: pskBytes),
  hostname: "device.local",
  trustRoots: nil
)
try await connection.connect()
```

```swift
import SwiftOCADevice

// PSK-only on Linux; cert + PSK both supported on Apple.
let endpoint = try await Ocp1TLSDatagramDeviceEndpoint(port: 65011)
try await endpoint.run()
```

Bonjour service type is `_ocasec._udp.` (`OcaNetworkAdvertisingServiceType.udpSecure`); connection prefix is `ocasec/udp`.

> **Cert + DTLS on Linux.** `Ocp1OpenSSLDTLSDeviceEndpoint` (and the matching client `Ocp1OpenSSLDTLSConnection`) reject non-PSK credentials at construction with `.notImplemented`. Cert-mode DTLS handshakes produce multi-record server flights that the current memory-BIO drain emits as one UDP write, which trips IP-level fragmentation or `EMSGSIZE` on most paths. A packet-preserving outbound path (per-record send, already wired for the PSK case) is on the roadmap to lift this; until then PSK is the only supported DTLS credential on Linux. Apple DTLS supports both PSK and cert.

### Server hardening knobs (Linux)

`Ocp1OpenSSLDTLSDeviceEndpoint` accepts four datagram-specific parameters with safe defaults; tune them for the deployment shape:

| Parameter             | Default     | Purpose                                                                                 |
| :---                  | :---        | :---                                                                                    |
| `maxPeers`            | 256         | Hard cap on simultaneous peer entries in the endpoint's controller table.               |
| `idleTimeout`         | 5 min       | Drop fully-handshaked peers that have stopped sending datagrams for this long.          |
| `handshakeDeadline`   | 10 s        | Drop peers whose handshake never completed within this window — typically spoof noise.  |
| `sourceAddressFilter` | `nil`       | Optional `(Data) -> Bool` gate; runs before any per-peer allocation. `nil` = accept all. |

A periodic GC sweep (5 s cadence) enforces the handshake and idle deadlines and is started from `run()`.

> **Operator requirement.** Defaults assume a trusted subnet. **Hostile-subnet deployments MUST** front the endpoint with one of: a restrictive `sourceAddressFilter` (subnet allowlist), an external firewall/ACL, or both. Also tighten `idleTimeout` (e.g. 30 s) and lower `maxPeers` to the expected steady-state controller count. The 2-per-source allocation throttle (10 s window) backstops these but **does not** stop distributed or spoofed multi-source floods on its own — without an upstream filter, a sustained spoofed flood can fill the peer table for ~`handshakeDeadline + sweep cadence`.

### Revocation checking (opt-in)

`Ocp1TLSRevocationOptions` enables CRL / OCSP checking. Empty `flags`
disables it (default); set `.enabled` to opt in. Off by default keeps
private-PKI deployments without a CRL/OCSP responder working unchanged.

| Backend      | With `.enabled`                                                                            |
| :---         | :---                                                                                       |
| Apple (NW)   | `SecPolicyCreateRevocation(kSecRevocationUseAnyAvailableMethod)` installed alongside the SSL policy. **Soft-fail**: an unreachable responder permits the chain. CRL data in `crls` is ignored — Security.framework fetches it on its own. |
| OpenSSL      | `crls` (PEM CRL bundle) are loaded into the X509 store and `X509_V_FLAG_CRL_CHECK` is armed. **Leaf-only by default, soft-fail with no CRLs supplied** — without loaded CRLs the flag would hard-fail every handshake, so we skip arming it. Add `.checkChain` to arm `X509_V_FLAG_CRL_CHECK_ALL`; the bundle MUST then carry every intermediate's CRL or OpenSSL hard-fails. |

Operators wiring this up should:

- Plumb a fresh CRL into `Ocp1TLSCRLBundle.crlData(...)` (or `.crlFile(...)` for a path); the OpenSSL store snapshots at endpoint init, so rotating CRLs requires an endpoint restart.
- On Apple, ensure the responder is reachable from the deployment subnet — soft-fail will silently permit chains otherwise.
- Prefer `.strict` (= `.enabled + .checkChain`) for new code. Use bare `.enabled` only when the bundle deliberately covers the leaf only.

### Audit logging

Three operator-visible signals fire at `info` / `warning` level so misconfigurations surface in logs instead of failing silently:

- **`TLS certificate verification is disabled (insecure)`** — emitted *once per connect* on the client side when `Ocp1ConnectionOptions.flags` contains `.disableCertificateVerification`. This flag is intentionally dev-only.
- **`<endpoint> requires client certificates (mTLS)`** — emitted at server startup (or, on Apple, at endpoint init) whenever `clientCertificateTrustRoots` is configured. Lets you confirm a server is enforcing mTLS without grepping a packet capture.
- **`TLS handshake failed or timed out: ...`** — emitted at `warning` for any inbound stream handshake that fails the 10 s deadline or returns an OpenSSL error. The error string is the OpenSSL queue contents; if the queue is empty the string is `(no detail in OpenSSL error queue)` rather than blank.

### DTLS handshake transport

- **Cookie exchange (RFC 6347 §4.2.1)** is enabled on the server: the first ClientHello from a new peer prompts a small HelloVerifyRequest with an HMAC-SHA256 cookie bound to the peer's source address. The peer must echo the cookie before any state-bearing handshake records flow back, blocking the basic DoS-amplification vector.
- **Retransmit watchdog**: a 200 ms ticker on both client and server drives `DTLSv1_handle_timeout` while the handshake is in flight. Without it, a single lost handshake datagram would stall the handshake indefinitely because the memory-BIO engine has no built-in scheduler.
- **MTU**: a conservative 1200-byte DTLS payload MTU is set up front (RFC 6347 §4.1.1 fallback). Outbound flights are split at the 13-byte DTLS record header (`sendDTLSRecords`) so each record ships in its own datagram, avoiding IP-level fragmentation. The cert-mode DTLS rejection above closes the remaining oversize-handshake case for Linux.

### Residual exposure

The cookie callback fires *inside* `SSL_do_handshake` on the per-peer engine, so the per-peer state (~30–60 KB) is still allocated when the first ClientHello arrives — only the *response* is bounded to a HelloVerifyRequest (~30–50 B). Four layers contain that exposure:

- **Per-source-IP rate limit** — a fixed-window throttle (2 fresh engine allocations per source IP per 10 s, keyed on the IP only so port rotation can't bypass) refuses spoofed-source ClientHello floods before any engine state is allocated. Refunded on construction failure / peer-table overflow.
- **Peer-table cap** (`maxPeers`, default 256) — backstops the per-source throttle.
- **Source-address filter** (`Ocp1OpenSSLDTLSEndpointOptions.sourceAddressFilter`) — optional pre-allocation hook that lets operators apply subnet allowlists / AF restrictions before any engine state is allocated.
- **Handshake-deadline GC** (default 10 s) — sweeps slots whose engine never reached `isHandshakeComplete`.

**Why we don't reimplement the DTLS pre-cookie path ourselves.** Eliminating the pre-engine allocation entirely would require either (a) using OpenSSL's `DTLSv1_listen` on a dedicated `BIO_dgram` socket, which conflicts with the IORing-driven UDP socket the rest of the endpoint uses, or (b) parsing DTLS record + ClientHello bytes ourselves to apply the cookie HMAC before allocation. (a) is a substantial architectural rework with regression risk that crosses two transport stacks; (b) means importing a chunk of the DTLS state machine into Swift, where any byte-counting bug would be a denial-of-service or worse on a security-critical path. The four containment layers above keep the residual exposure bounded for trusted-subnet deployments. **Hostile-subnet deployments MUST configure `sourceAddressFilter` or an upstream firewall/ACL** — the containment layers alone are not sufficient when an attacker can source from arbitrary IPs.

DTLS-over-UDP has no graceful close. Peers that disconnect ungracefully linger until `idleTimeout` elapses.

The DTLS server binds to `INADDR_ANY` by default — pass an explicit `sockaddr_in` / `sockaddr_in6` to the `address:` initializer to scope to a specific interface.

## Transport abstraction (Linux server)

The OpenSSL-backed server controllers are decoupled from the IORing socket type via two protocols in `SwiftOCASecure`:

- **`Ocp1ByteStream`** — TCP-like reliable byte stream (`read` / `write` / `close`). Used by `Ocp1OpenSSLStreamController` to drive TLS over any byte transport.
- **`Ocp1DatagramChannel`** — outbound per-peer datagram send (`send` / `close`). Used by `Ocp1OpenSSLDTLSController` to emit ciphertext for a single bound peer.

Two adapters live in `SwiftOCASecureDevice` and are wired up automatically by the existing endpoint convenience inits:

- `IORingByteStream` — wraps an `IORing.Socket` for TLS
- `_EndpointDatagramChannel` — routes per-peer DTLS sends through the endpoint's shared UDP socket; holds a weak endpoint reference so teardown surfaces as `Ocp1Error.notConnected`

Day-to-day callers don't need to interact with these directly — the standard `Ocp1OpenSSLStreamDeviceEndpoint(port:credential:…)` and `Ocp1OpenSSLDTLSDeviceEndpoint(port:credential:…)` inits remain the recommended entry points and continue to wire IORing under the hood.

The protocols exist so the engine can be exercised end-to-end against an in-memory transport for testing — see `Tests/SwiftOCADeviceTests/PipeByteStream.swift` and `OpenSSLEnginePipeTests.swift`. PSK and certificate-mode handshakes (including mTLS coexistence with PSK) round-trip in ~80 ms per case over the in-memory pipe with no socket / port / accept-loop state shared between cases. The same pattern also leaves the door open for future alternative transports (e.g. FlyingSocks-backed TLS) without further engine changes.

A future refactor (Phase 2) will lift this further by introducing `Ocp1ByteStreamListener` and dropping `Ocp1OpenSSLStreamDeviceEndpoint`'s `Ocp1IORingDeviceEndpoint` inheritance entirely, making the endpoint itself transport-pluggable. That is intentionally out of scope for the current branch.

## `ocacli` examples

The `tls` branch of `ocacli` exposes the credential / trust-roots API as command-line flags:

```sh
# PSK against a device on the local network, default OCA-PSK identity
ocacli -S -K $(printf '%.0s00' {1..32}) device.local:65010

# Custom PSK identity
ocacli -S --psk-identity my-controller -K <hex> device.local:65010

# PEM cert / key, with a private CA bundle for the device cert
ocacli -S --cert-file client.crt --key-file client.key --cacert ca.pem device.local:65010

# PKCS#12 bundle
ocacli -S --pkcs12 client.p12 --pkcs12-password secret device.local:65010

# Development: skip server cert verification (matches curl --insecure)
ocacli -S --insecure device.local:65010
```

`-S` / `--tls` enables TLS. The flag is currently mutually exclusive with `-U` (UDP). DTLS support in `ocacli` is not yet wired up; the underlying `Ocp1TLSDatagramConnection` is fully functional and can be driven from the library directly (see the DTLS section above).

## Example device

[`Examples/OCADevice/DeviceApp.swift`](../Examples/OCADevice/DeviceApp.swift) reads TLS configuration from environment variables for easy testing:

```sh
# Run the example with a real cert and an mTLS client trust bundle
OCA_TLS_CERT_FILE=device.crt \
OCA_TLS_KEY_FILE=device.key \
OCA_TLS_CLIENT_CA_FILE=client-ca.pem \
swift run OCADevice

# Or with a PKCS#12 bundle
OCA_TLS_PKCS12_FILE=device.p12 \
OCA_TLS_PKCS12_PASSWORD=secret \
swift run OCADevice
```

With no env vars set, the example preloads a zero PSK under the `OCA-PSK` identity so the secure endpoint and Bonjour advertisement work out of the box. The zero PSK is _not_ a real credential — replace it before exposing the endpoint to a network.
