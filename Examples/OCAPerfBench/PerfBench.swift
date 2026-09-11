//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

// OCP.1 performance harness, written against the OCP.1 API so that the same source
// measures any two revisions of SwiftOCA: see README.md and compare.sh.
//
// Prints one machine-readable line per benchmark, in ns/op unless its name says
// otherwise:
//   RESULT <name> <min> <median> <max> <samples>
// and, in profile mode, one line with the round trips completed:
//   PROFILE <count> round trips in <seconds>s <transport>

import Foundation
import SwiftOCA
import SwiftOCADevice

/// `Ocp1DeviceEndpoint` is the portable stream endpoint (FlyingSocks on Darwin,
/// IORing on Linux); there is no such alias for datagrams, so name one here.
#if os(Linux)
typealias BenchDatagramDeviceEndpoint = Ocp1IORingDatagramDeviceEndpoint
#else
typealias BenchDatagramDeviceEndpoint = Ocp1FlyingSocksDatagramDeviceEndpoint
#endif

nonisolated(unsafe) var sink: UInt64 = 0

// MARK: - measurement

private func nanoseconds(_ d: Duration) -> Double {
  let c = d.components
  return Double(c.seconds) * 1e9 + Double(c.attoseconds) / 1e9
}

private func report(_ name: String, _ nsPerOp: [Double]) {
  let s = nsPerOp.sorted()
  let figures = [s.first ?? 0, s[s.count / 2], s.last ?? 0].map { String(format: "%.1f", $0) }
  print((["RESULT", name] + figures + ["\(s.count)"]).joined(separator: "\t"))
  // flush every stream: on Glibc `stdout` is a global var, which Swift 6 rejects as a
  // data race to name
  fflush(nil)
}

func bench(_ name: String, reps: Int = 7, iters: Int, _ body: () throws -> ()) {
  do {
    for _ in 0..<min(iters, 2000) { try body() }
    var samples = [Double]()
    for _ in 0..<reps {
      let start = ContinuousClock.now
      for _ in 0..<iters { try body() }
      samples.append(nanoseconds(ContinuousClock.now - start) / Double(iters))
    }
    report(name, samples)
  } catch {
    print("SKIP\t\(name)\t\(error)")
  }
}

func benchAsync(
  _ name: String,
  reps: Int = 5,
  iters: Int,
  _ body: () async throws -> ()
) async {
  do {
    for _ in 0..<min(iters, 200) { try await body() }
    var samples = [Double]()
    for _ in 0..<reps {
      let start = ContinuousClock.now
      for _ in 0..<iters { try await body() }
      samples.append(nanoseconds(ContinuousClock.now - start) / Double(iters))
    }
    report(name, samples)
  } catch {
    print("SKIP\t\(name)\t\(error)")
  }
}

// MARK: - fixtures

/// A four-byte scalar parameter, as a gain setter carries.
private let smallParameters = Ocp1Parameters(
  parameterCount: 1,
  parameterData: Data([0x3F, 0x80, 0x00, 0x00])
)

/// A parameter block the size of a long string or a member list.
private func parameters(bytes: Int) -> Ocp1Parameters {
  Ocp1Parameters(parameterCount: 1, parameterData: Data(repeating: 0xAB, count: bytes))
}

private func command(_ parameters: Ocp1Parameters) -> Ocp1Command {
  Ocp1Command(
    commandSize: 0,
    handle: 1,
    targetONo: OcaDeviceManagerONo,
    methodID: OcaMethodID("3.4"),
    parameters: parameters
  )
}

private func response(_ parameters: Ocp1Parameters) -> Ocp1Response {
  Ocp1Response(responseSize: 0, handle: 1, statusCode: .ok, parameters: parameters)
}

// MARK: - codec and framing

/// PDU encode/decode at several parameter sizes, one message per PDU and eight
/// batched, for both directions.
func runCodecBenchmarks() throws {
  for (label, payload) in [
    ("small", smallParameters),
    ("1k", parameters(bytes: 1024)),
    ("8k", parameters(bytes: 8192)),
  ] {
    let iters = payload.parameterData.count > 4096 ? 20_000 : 100_000
    let aCommand = command(payload)
    let aResponse = response(payload)
    let commands8 = [Ocp1Message](repeating: aCommand, count: 8)
    let responses8 = [Ocp1Message](repeating: aResponse, count: 8)
    let commandPdu1 = try Ocp1Connection.encodeOcp1MessagePdu([aCommand], type: .ocaCmdRrq)
    let commandPdu8 = try Ocp1Connection.encodeOcp1MessagePdu(commands8, type: .ocaCmdRrq)
    let responsePdu1 = try Ocp1Connection.encodeOcp1MessagePdu([aResponse], type: .ocaRsp)
    let responsePdu8 = try Ocp1Connection.encodeOcp1MessagePdu(responses8, type: .ocaRsp)

    bench("encodePdu.command.1.\(label)", iters: iters) {
      let d: Data = try Ocp1Connection.encodeOcp1MessagePdu([aCommand], type: .ocaCmdRrq)
      sink &+= UInt64(d.count)
    }
    bench("encodePdu.command.8.\(label)", iters: iters / 4) {
      let d: Data = try Ocp1Connection.encodeOcp1MessagePdu(commands8, type: .ocaCmdRrq)
      sink &+= UInt64(d.count)
    }
    bench("decodePdu.command.1.\(label)", iters: iters) {
      let m = try Ocp1Connection.decodeOcp1MessagePdu(from: commandPdu1).1
      sink &+= UInt64(m.count)
    }
    bench("decodePdu.command.8.\(label)", iters: iters / 4) {
      let m = try Ocp1Connection.decodeOcp1MessagePdu(from: commandPdu8).1
      sink &+= UInt64(m.count)
    }
    bench("encodePdu.response.1.\(label)", iters: iters) {
      let d: Data = try Ocp1Connection.encodeOcp1MessagePdu([aResponse], type: .ocaRsp)
      sink &+= UInt64(d.count)
    }
    bench("decodePdu.response.1.\(label)", iters: iters) {
      let m = try Ocp1Connection.decodeOcp1MessagePdu(from: responsePdu1).1
      sink &+= UInt64(m.count)
    }
    bench("decodePdu.response.8.\(label)", iters: iters / 4) {
      let m = try Ocp1Connection.decodeOcp1MessagePdu(from: responsePdu8).1
      sink &+= UInt64(m.count)
    }
  }

  // parameter marshaling, as a command handler sees it
  let modelDescription = OcaModelDescription(
    manufacturer: "PADL",
    name: "SwiftOCA",
    version: "0.0"
  )
  let encodedModelDescription: Data = try Ocp1Encoder().encode(modelDescription)
  let gain: OcaFloat32 = -12.5
  let encodedGain: Data = try Ocp1Encoder().encode(gain)

  bench("encode.float32", iters: 200_000) {
    let d: Data = try Ocp1Encoder().encode(gain)
    sink &+= UInt64(d.count)
  }
  bench("decode.float32", iters: 200_000) {
    let v = try Ocp1Decoder().decode(OcaFloat32.self, from: encodedGain)
    sink &+= UInt64(v.bitPattern)
  }
  bench("encode.modelDescription", iters: 100_000) {
    let d: Data = try Ocp1Encoder().encode(modelDescription)
    sink &+= UInt64(d.count)
  }
  bench("decode.modelDescription", iters: 100_000) {
    let v = try Ocp1Decoder().decode(OcaModelDescription.self, from: encodedModelDescription)
    sink &+= UInt64(v.name.count)
  }
  for size in [64, 1024, 8192] {
    let blob = OcaBlob(Data(repeating: 0xAB, count: size))
    let encoded: Data = try Ocp1Encoder().encode(blob)
    bench("encode.blob\(size)", iters: 100_000) {
      let d: Data = try Ocp1Encoder().encode(blob)
      sink &+= UInt64(d.count)
    }
    bench("decode.blob\(size)", iters: 100_000) {
      let v = try Ocp1Decoder().decode(OcaBlob.self, from: encoded)
      sink &+= UInt64(v.count)
    }
  }
}

// MARK: - end to end

private func localhostAddress(port: UInt16) -> Data {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
  #if canImport(Darwin)
  addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: addr) { Data($0) }
}

/// GetDeviceName: an empty command, a short response.
private let getDeviceName = Ocp1Command(
  commandSize: 0,
  handle: 0,
  targetONo: OcaDeviceManagerONo,
  methodID: OcaMethodID("3.4"),
  parameters: Ocp1Parameters()
)

private let benchBlockONo: OcaONo = 0x0001_0001

/// SetLabel on the bench block: a large command, an empty response.
private func setLabel(_ text: String) throws -> Ocp1Command {
  try Ocp1Command(
    commandSize: 0,
    handle: 0,
    targetONo: benchBlockONo,
    methodID: OcaMethodID("2.9"),
    parameters: Ocp1Parameters(parameterCount: 1, parameterData: Ocp1Encoder().encode(text))
  )
}

/// GetLabel on the bench block: an empty command, a large response.
private let getLabel = Ocp1Command(
  commandSize: 0,
  handle: 0,
  targetONo: benchBlockONo,
  methodID: OcaMethodID("2.8"),
  parameters: Ocp1Parameters()
)

/// Drives the same three exchanges over whichever transport is handed in, so the
/// per-transport figures differ only in the transport.
private func runRoundTrips(_ transport: String, _ connection: Ocp1Connection) async {
  await benchAsync("roundtrip.\(transport).getDeviceName", iters: 2000) {
    let response = try await connection.sendCommandRrq(getDeviceName)
    sink &+= UInt64(response.statusCode.rawValue)
  }

  do {
    let large = String(repeating: "x", count: 1000)
    let command = try setLabel(large)
    await benchAsync("roundtrip.\(transport).setLabel.1k", iters: 2000) {
      let response = try await connection.sendCommandRrq(command)
      sink &+= UInt64(response.statusCode.rawValue)
    }
    await benchAsync("roundtrip.\(transport).getLabel.1k", iters: 2000) {
      let response = try await connection.sendCommandRrq(getLabel)
      sink &+= UInt64(response.parameters.parameterData.count)
    }
    // the same exchange as the first benchmark, but no longer the first thing the
    // connection does: tells an ordering artefact apart from a real difference
    await benchAsync("roundtrip.\(transport).getDeviceName.late", iters: 2000) {
      let response = try await connection.sendCommandRrq(getDeviceName)
      sink &+= UInt64(response.statusCode.rawValue)
    }
  } catch {
    print("SKIP\troundtrip.\(transport).label\t\(error)")
  }
}

func makeBenchDevice() async throws
  -> (OcaDevice, SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>)
{
  let device = OcaDevice.shared
  try await device.initializeDefaultObjects()
  let block = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
    objectNumber: benchBlockONo,
    role: "bench",
    deviceDelegate: device,
    addToRootBlock: true
  )
  return (device, block)
}

enum BenchError: Error {
  case unknownTransport(String)
  case needsPort(String)
}

/// Runs `body` with a controller connected over `transport` (local, tcp or udp) to an
/// endpoint of its own. The local transport hands whole PDUs across a channel, so its
/// figures are the coding and dispatch path with the transport taken out.
func withConnection(
  _ transport: String,
  _ device: OcaDevice,
  port: UInt16,
  _ body: (Ocp1Connection) async throws -> ()
) async throws {
  switch transport {
  case "local":
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    defer { endpointTask.cancel() }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    try await body(connection)
    try await connection.disconnect()
  case "tcp":
    guard port != 0 else { throw BenchError.needsPort(transport) }
    let endpoint = try await Ocp1DeviceEndpoint(
      address: localhostAddress(port: port),
      timeout: .seconds(5),
      device: device
    )
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    defer { endpointTask.cancel() }
    try await Task.sleep(for: .milliseconds(500))
    let connection = try await Ocp1TCPConnection(
      deviceAddress: localhostAddress(port: port),
      options: Ocp1ConnectionOptions()
    )
    try await connection.connect()
    try await body(connection)
    try await connection.disconnect()
  case "udp":
    guard port != 0 else { throw BenchError.needsPort(transport) }
    let endpoint = try await BenchDatagramDeviceEndpoint(
      address: localhostAddress(port: port),
      timeout: .seconds(5),
      device: device
    )
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    defer { endpointTask.cancel() }
    try await Task.sleep(for: .milliseconds(500))
    let connection = try await Ocp1UDPConnection(
      deviceAddress: localhostAddress(port: port),
      options: Ocp1ConnectionOptions()
    )
    try await connection.connect()
    try await body(connection)
    try await connection.disconnect()
  default:
    throw BenchError.unknownTransport(transport)
  }
}

func runLocalBenchmarks(_ device: OcaDevice) async throws {
  try await withConnection("local", device, port: 0) { await runRoundTrips("local", $0) }
}

func runTCPBenchmarks(_ device: OcaDevice, port: UInt16) async throws {
  try await withConnection("tcp", device, port: port) { await runRoundTrips("tcp", $0) }
}

func runUDPBenchmarks(_ device: OcaDevice, port: UInt16) async throws {
  try await withConnection("udp", device, port: port) { await runRoundTrips("udp", $0) }
}

/// Peak resident memory in KiB: VmHWM from /proc on Linux, ru_maxrss elsewhere.
private func peakMemoryKiB() -> Double {
  #if os(Linux)
  guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
        let line = status.split(separator: "\n").first(where: { $0.hasPrefix("VmHWM:") })
  else { return 0 }
  let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
  return fields.count > 1 ? Double(fields[1]) ?? 0 : 0
  #else
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  return Double(usage.ru_maxrss) / 1024 // bytes on Darwin
  #endif
}

/// `n` zero-padded to `width` digits, so that a series sorts in order.
private func padded(_ n: Int, _ width: Int) -> String {
  let digits = String(n)
  return String(repeating: "0", count: max(0, width - digits.count)) + digits
}

/// Nothing but the smallest round trip, for as long as asked: gives a profiler a
/// steady state to sample rather than a mixture of exchanges. Each `slice` seconds is
/// reported separately, so a cost that grows with the number of requests shows as a
/// rising series, and the peak memory at the end.
func runProfileLoop(
  _ device: OcaDevice,
  transport: String,
  port: UInt16,
  seconds: Double,
  slice: Double
) async throws {
  try await withConnection(transport, device, port: port) { connection in
    try await profileLoop(connection, transport: transport, seconds: seconds, slice: slice)
  }
  report("profile.\(transport).maxrss.KiB", [peakMemoryKiB()])
}

private func profileLoop(
  _ connection: Ocp1Connection,
  transport: String,
  seconds: Double,
  slice: Double
) async throws {
  let start = ContinuousClock.now
  let end = start + .seconds(seconds)
  var sliceStart = start
  var slices = 0
  var inSlice = 0
  var total = 0
  while true {
    let now = ContinuousClock.now
    if now >= end || now >= sliceStart + .seconds(slice) {
      if inSlice > 0 {
        slices += 1
        let label = "profile.\(transport).t\(padded(Int((Double(slices) * slice).rounded()), 4))s"
        report(label, [nanoseconds(now - sliceStart) / Double(inSlice)])
      }
      if now >= end { break }
      sliceStart = now
      inSlice = 0
    }
    let response = try await connection.sendCommandRrq(getDeviceName)
    sink &+= UInt64(response.statusCode.rawValue)
    inSlice += 1
    total += 1
  }
  print("PROFILE\t\(total) round trips in \(seconds)s\t\(transport)")
}

/// Round-trip time from the moment of connection, in consecutive blocks of
/// `blockSize` with no warm-up, over `connections` fresh connections in turn: shows
/// whether the first exchanges on a connection cost more, for how long, and whether
/// every connection pays it or only the first in the process.
func runConnectTimeline(
  _ device: OcaDevice,
  transport: String,
  port: UInt16,
  connections: Int,
  blocks: Int,
  blockSize: Int
) async throws {
  guard connections > 0, blocks > 0, blockSize > 0 else { return }
  var samples = [[Double]](repeating: [], count: blocks)
  for n in 0..<connections {
    // a port pair of its own for each connection, so no endpoint waits on the last one's
    let connectionPort = port == 0 ? 0 : port + UInt16(2 * n)
    try await withConnection(transport, device, port: connectionPort) { connection in
      for block in 0..<blocks {
        let start = ContinuousClock.now
        for _ in 0..<blockSize {
          let response = try await connection.sendCommandRrq(getDeviceName)
          sink &+= UInt64(response.statusCode.rawValue)
        }
        samples[block].append(nanoseconds(ContinuousClock.now - start) / Double(blockSize))
      }
    }
  }
  for (block, values) in samples.enumerated() {
    report("connect.\(transport).block\(padded(block + 1, 3))", values)
  }
  for n in 0..<connections {
    report("connect.\(transport).firstblock.c\(padded(n + 1, 2))", [samples[0][n]])
  }
  // A connection can run at one of two speeds for its whole life, so the block medians
  // above move with how many connections came up slow. Each connection's own mean shows
  // which ones did.
  for n in 0..<connections {
    let mean = samples.reduce(0) { $0 + $1[n] } / Double(blocks)
    report("connect.\(transport).connection.c\(padded(n + 1, 2))", [mean])
  }
}

/// Device-to-controller notification pipeline: N property changes on the device,
/// timed until the controller observes the last one. Intermediate values may be
/// coalesced by the property subject, so the observed count is reported too.
func runNotificationBenchmark(
  _ device: OcaDevice,
  _ deviceBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>,
  sets: Int
) async throws {
  let endpoint = try await OcaLocalDeviceEndpoint(device: device)
  let endpointTask = Task { do { try await endpoint.run() } catch {} }
  defer { endpointTask.cancel() }
  let connection = await OcaLocalConnection(endpoint)
  try await connection.connect()

  let clientBlock: SwiftOCA.OcaBlock = try await connection.resolve(
    object: OcaObjectIdentification(
      oNo: benchBlockONo,
      classIdentification: SwiftOCA.OcaBlock.classIdentification
    )
  )
  await clientBlock.$label.subscribe(clientBlock)
  try await Task.sleep(for: .milliseconds(500))

  let last = "label-\(sets - 1)"
  let observed = Counter()
  let done = Counter()
  let consumer = Task {
    for try await result in clientBlock.$label.async {
      observed.increment()
      if case let .success(value) = result, value as? OcaString == last {
        done.increment()
        return
      }
    }
  }
  defer { consumer.cancel() }

  let start = ContinuousClock.now
  for i in 0..<sets {
    let value = "label-\(i)"
    await { @OcaDevice in deviceBlock.label = value }()
  }
  let deadline = ContinuousClock.now + .seconds(30)
  while done.value == 0, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  let elapsed = nanoseconds(ContinuousClock.now - start)

  if done.value == 0 {
    print("SKIP\tnotify.local.propertyChanged\tlast value never observed")
  } else {
    report("notify.local.propertyChanged", [elapsed / Double(sets)])
    print("INFO\tnotify.local.observed\t\(observed.value)\tof\t\(sets)")
  }
  try await connection.disconnect()
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value = 0
  var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
  func increment() { lock.lock(); _value += 1; lock.unlock() }
}

// MARK: - main

@main
enum PerfBench {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    let port = UInt16(environment["BENCH_PORT"] ?? "") ?? 0
    let only = environment["BENCH_ONLY"]

    if only == nil || only == "codec" {
      try runCodecBenchmarks()
    }
    if only == "profile" {
      let (device, _) = try await makeBenchDevice()
      let transport = environment["BENCH_TRANSPORT"] ?? "local"
      let seconds = Double(environment["BENCH_SECONDS"] ?? "20") ?? 20
      let slice = Double(environment["BENCH_SLICE"] ?? "5") ?? 5
      try await runProfileLoop(device, transport: transport, port: port, seconds: seconds, slice: slice)
      return
    }
    if only == "connect" {
      let (device, _) = try await makeBenchDevice()
      try await runConnectTimeline(
        device,
        transport: environment["BENCH_TRANSPORT"] ?? "tcp",
        port: port,
        connections: Int(environment["BENCH_CONNECTIONS"] ?? "5") ?? 5,
        blocks: Int(environment["BENCH_BLOCKS"] ?? "40") ?? 40,
        blockSize: Int(environment["BENCH_BLOCK_SIZE"] ?? "500") ?? 500
      )
      return
    }
    if only == nil || only == "e2e" || only == "notify" {
      let (device, block) = try await makeBenchDevice()
      if only != "notify" {
        do { try await runLocalBenchmarks(device) }
        catch { print("SKIP\troundtrip.local\t\(error)") }
      }
      if port != 0, only != "notify" {
        do { try await runTCPBenchmarks(device, port: port) }
        catch { print("SKIP\troundtrip.tcp\t\(error)") }
        do { try await runUDPBenchmarks(device, port: port + 1) }
        catch { print("SKIP\troundtrip.udp\t\(error)") }
      }
      do { try await runNotificationBenchmark(device, block, sets: 2000) }
      catch { print("SKIP\tnotify.local.propertyChanged\t\(error)") }
    }

    if sink == 0x1234_5678 { print("") } // keep the optimiser honest
  }
}
