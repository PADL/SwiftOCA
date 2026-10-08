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

#if NonEmbeddedBuild

import FlyingSocks
import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftOCAXMI
import SwiftOCAXMIDevice
import XCTest

/// Writes class manager descriptors as XMI and reads them back.
final class XMIExportTests: XCTestCase {
  /// A device with objects of several kinds of class, among them a deprecated one.
  @OcaDevice
  static func device() async throws -> (OcaDevice, SwiftOCADevice.OcaClassManager) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await SwiftOCADevice.OcaGain(role: "Gain", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaMute(role: "Mute", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaSwitch(role: "Switch", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaLevelSensor(role: "Level", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaIdentificationSensor(role: "Identify", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaDelayExtended(role: "Delay", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaTimeSource(role: "Time", deviceDelegate: device)
    // made after the objects, so it describes what the device already has
    return try await (device, SwiftOCADevice.OcaClassManager(deviceDelegate: device))
  }

  /// Each way `ours` and `theirs` differ, by element, so a failure says where.
  private static func differences(
    _ ours: (classes: [OcaClassDescriptor], datatypes: [OcaDatatypeDescriptor]),
    _ theirs: (classes: [OcaClassDescriptor], datatypes: [OcaDatatypeDescriptor])
  ) -> [String] {
    var differences = [String]()
    if ours.classes.map(\.name) != theirs.classes.map(\.name) {
      differences.append("classes: \(ours.classes.map(\.name)) vs \(theirs.classes.map(\.name))")
    }
    for (a, b) in zip(ours.classes, theirs.classes) where a != b {
      for (p, q) in zip(a.properties, b.properties) where p != q { differences.append("\(a.name) property: \(p) vs \(q)") }
      for (m, n) in zip(a.methods, b.methods) where m != n { differences.append("\(a.name) method: \(m) vs \(n)") }
      for (e, f) in zip(a.events, b.events) where e != f { differences.append("\(a.name) event: \(e) vs \(f)") }
      if a.properties.count != b.properties.count || a.methods.count != b.methods.count || a.events.count != b.events.count
        || a.classVersion != b.classVersion || a.isDeprecated != b.isDeprecated || a.documentation != b.documentation
      {
        differences.append("\(a.name): \(a) vs \(b)")
      }
    }
    let theirTypes = Dictionary(theirs.datatypes.map { ($0.name, $0) }) { first, _ in first }
    for d in ours.datatypes where theirTypes[d.name] != d {
      differences.append("datatype \(d.name): \(d) vs \(theirTypes[d.name].map { "\($0)" } ?? "missing")")
    }
    let ourNames = Set(ours.datatypes.map(\.name))
    for d in theirs.datatypes where !ourNames.contains(d.name) {
      differences.append("datatype \(d.name): only read back")
    }
    return differences
  }

  @OcaDevice
  func testADevicesDescriptorsReadBackAsWritten() async throws {
    let (device, manager) = try await Self.device()
    defer { withExtendedLifetime(device) {} }
    let classes = manager.controlClasses
    let datatypes = manager.datatypes
    XCTAssertGreaterThan(classes.count, 10)
    XCTAssertGreaterThan(datatypes.count, 50)
    XCTAssertTrue(classes.contains(where: \.isDeprecated))
    let document = OcaXMIExport.document(classes: classes, datatypes: datatypes)
    let model = try OcaXMIModel(data: Data(document.utf8))
    XCTAssertEqual(Self.differences((classes, datatypes), (model.classes, model.datatypes)), [])
    XCTAssertEqual(model.classes, classes)
    XCTAssertEqual(model.datatypes, datatypes)
  }

  func testTheModelReadsBackAsWritten() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "AES70-2-excerpt", withExtension: "xmi", subdirectory: "Resources"))
    let model = try OcaXMIModel(contentsOf: url)
    let document = OcaXMIExport.document(classes: model.classes, datatypes: model.datatypes)
    let again = try OcaXMIModel(data: Data(document.utf8))
    XCTAssertEqual(Self.differences((model.classes, model.datatypes), (again.classes, again.datatypes)), [])
    XCTAssertEqual(again.classes, model.classes)
    XCTAssertEqual(again.datatypes, model.datatypes)
  }

  #if canImport(FlyingFox)
  @OcaDevice
  func testTheClassManagerServesItsModel() async throws {
    let (device, manager) = try await Self.device()
    defer { withExtendedLifetime(device) {} }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
    #if canImport(Darwin)
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    let endpoint = try await OcaFlyingFoxDeviceEndpoint(
      address: withUnsafeBytes(of: address) { Data($0) },
      timeout: .seconds(5),
      device: device
    )
    XCTAssertEqual(manager.modelURL, "")
    await manager.serveModel(on: endpoint, host: "127.0.0.1")
    // bound to port 0, so ModelURL waits for the port the system chooses
    XCTAssertEqual(manager.modelURL, "")
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }
    try await endpoint.waitUntilListening()
    let listeningPort = await endpoint.listeningPort
    let port = try XCTUnwrap(listeningPort)
    for _ in 0..<500 where manager.modelURL.isEmpty {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(manager.modelURL, "http://127.0.0.1:\(port)/aes70/model.xmi")
    // a second time on the same endpoint changes nothing a controller sees
    await manager.serveModel(on: endpoint, host: "127.0.0.1")
    XCTAssertEqual(manager.modelURL, "http://127.0.0.1:\(port)/aes70/model.xmi")

    let (status, contentType, body) = try await Self.get(manager.modelURL)
    XCTAssertEqual(status, 200)
    XCTAssertEqual(contentType, "application/xml; charset=utf-8")
    let model = try OcaXMIModel(data: body)
    XCTAssertEqual(model.classes, manager.controlClasses)
    XCTAssertEqual(model.datatypes, manager.datatypes)

    // what a later object brings is in the next document
    XCTAssertFalse(model.classes.contains { $0.classID == SwiftOCADevice.OcaPolarity.classID })
    _ = try await SwiftOCADevice.OcaPolarity(role: "Polarity", deviceDelegate: device)
    let (_, _, later) = try await Self.get(manager.modelURL)
    XCTAssertTrue(try OcaXMIModel(data: later).classes.contains { $0.classID == SwiftOCADevice.OcaPolarity.classID })
  }

  /// A GET of an http URL on this host over a plain socket: its status, content type and body.
  private static func get(_ url: String) async throws -> (Int, String?, Data) {
    let components = try XCTUnwrap(URLComponents(string: url))
    let port = try UInt16(XCTUnwrap(components.port))
    let path = components.path
    let socket = try await AsyncSocket.connected(to: .inet(ip4: XCTUnwrap(components.host), port: port))
    defer { try? socket.close() }
    try await socket.write(Data("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n".utf8))
    var head = [UInt8]()
    while !head.suffix(4).elementsEqual("\r\n\r\n".utf8) {
      try head.append(await socket.read())
    }
    let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
    let status = lines.first.flatMap { Int($0.split(separator: " ").dropFirst().first ?? "") } ?? 0
    var headers = [String: String]()
    for line in lines.dropFirst() {
      let field = line.split(separator: ":", maxSplits: 1)
      guard field.count == 2 else { continue }
      headers[field[0].lowercased()] = field[1].trimmingCharacters(in: .whitespaces)
    }
    let length = headers["content-length"].flatMap(Int.init) ?? 0
    return try await (status, headers["content-type"], Data(socket.read(bytes: length)))
  }

  func testModelURLsAreAbsoluteAndBracketIPv6() {
    XCTAssertEqual(OcaModelURL.url(host: "127.0.0.1", port: 8080, path: "/aes70/model.xmi"), "http://127.0.0.1:8080/aes70/model.xmi")
    XCTAssertEqual(OcaModelURL.url(host: "fe80::1", port: 80, path: "model.xmi"), "http://[fe80::1]:80/model.xmi")
    XCTAssertEqual(OcaModelURL.url(host: "[::1]", port: 80, path: "/m"), "http://[::1]:80/m")
    XCTAssertTrue(OcaModelURL.defaultHost.contains("."))
  }
  #endif

  /// What the model's own form cannot say is tagged, and reads back as written; what
  /// XML cannot hold is replaced, and documentation and method order are as a class
  /// manager has them.
  func testWhatOnlyTagsCanSayReadsBack() throws {
    let datatypes = [
      OcaDatatypeDescriptor(name: "PadlBig", kind: .enum, baseTypeName: "OcaUint32", items: [
        OcaEnumItemDescriptor(name: "One", value: 1),
      ]),
      OcaDatatypeDescriptor(name: "PadlGain", kind: .typedef, baseTypeName: "OcaFloat32"),
      OcaDatatypeDescriptor(name: "PadlFlags", kind: .bitset, baseTypeName: "OcaUint32"),
      OcaDatatypeDescriptor(name: "PadlThing", kind: .struct, fields: [
        OcaFieldDescriptor(name: "Gain", typeName: "PadlGain"),
        OcaFieldDescriptor(name: "Trim", typeName: "PadlGain"),
      ]),
      OcaDatatypeDescriptor(name: "PadlPair", kind: .struct, typeArguments: ["T"], fields: [
        OcaFieldDescriptor(name: "First", typeName: "T"),
        OcaFieldDescriptor(name: "Second", typeName: "T"),
      ], documentation: "  bell\u{7}and\u{FFFE}  "),
    ]
    let classes = [OcaClassDescriptor(classID: "1.1", classVersion: 2, name: "PadlWorker", properties: [], methods: [
      OcaClassMethodDescriptor(methodID: "2.2", name: "Second", parameters: []),
      OcaClassMethodDescriptor(methodID: "2.1", name: "First", parameters: []),
    ])]
    let model = try OcaXMIModel(data: Data(OcaXMIExport.document(classes: classes, datatypes: datatypes).utf8))
    var expected = datatypes
    expected[4].documentation = "bell\u{FFFD}and\u{FFFD}"
    XCTAssertEqual(model.datatypes, expected.sorted { $0.name < $1.name })
    XCTAssertEqual(model.classes.first?.methods.map(\.name), ["First", "Second"])
  }

  func testADocumentXMLCannotHoldIsAnError() {
    let document = "<?xml version=\"1.0\"?><xmi:XMI xmlns:xmi=\"x\"><a b=\"\u{7}\"/></xmi:XMI>"
    XCTAssertThrowsError(try OcaXMIModel(data: Data(document.utf8)))
  }

  @OcaDevice
  func testTheSameModelWritesTheSameDocument() async throws {
    let (device, manager) = try await Self.device()
    defer { withExtendedLifetime(device) {} }
    let first = OcaXMIExport.document(classes: manager.controlClasses, datatypes: manager.datatypes)
    let second = OcaXMIExport.document(classes: manager.controlClasses, datatypes: manager.datatypes)
    XCTAssertEqual(first, second)
    XCTAssertTrue(first.contains(#"<uml:Model xmi:type="uml:Model" name="Device""#))
    // XMI IDs are unique within a document
    let ids = first.components(separatedBy: #"xmi:id=""#).dropFirst().map { $0.prefix { $0 != "\"" } }
    XCTAssertEqual(Set(ids).count, ids.count)
  }
}
#endif
