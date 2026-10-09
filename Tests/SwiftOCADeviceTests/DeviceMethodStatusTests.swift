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

import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

/// The status every class answers every method with, for a command carrying no
/// parameters, on OCP.1 and OCP.2, unlocked and under each lock held by another
/// controller. Recorded in `Resources/DeviceMethodStatuses.json`, so a change to the way
/// a method is dispatched shows up as a diff of that file. `SWIFTOCA_UPDATE_GOLDEN=1`
/// rewrites it.
///
/// The method IDs probed are every `OcaMethodID("x.y")` literal in SwiftOCADevice's
/// sources, plus each class's property accessors and `deviceMethods`; a class is listed
/// with an ID only where some probe answers other than NotImplemented, which is what an
/// unknown method returns. That bounds the probe to IDs the code names, without having to
/// attribute source files to classes.
final class DeviceMethodStatusTests: XCTestCase {
  private static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  private static let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/DeviceMethodStatuses.json")

  @OcaDevice
  func testEveryMethodAnswersAsRecorded() async throws {
    let lines = try await Self.probeEverything()
    let text = "[\n" + lines.joined(separator: ",\n") + "\n]\n"

    if ProcessInfo.processInfo.environment["SWIFTOCA_UPDATE_GOLDEN"] == "1" {
      try text.write(to: Self.fixture, atomically: true, encoding: .utf8)
      return
    }

    let recorded = try String(contentsOf: Self.fixture, encoding: .utf8)
    let recordedLines = Set(recorded.split(separator: "\n").map(String.init))
    let currentLines = Set(text.split(separator: "\n").map(String.init))
    let missing = recordedLines.subtracting(currentLines).sorted()
    let unexpected = currentLines.subtracting(recordedLines).sorted()
    XCTAssertTrue(
      missing.isEmpty && unexpected.isEmpty,
      """
      device method statuses differ from \(Self.fixture.path); \
      rerun with SWIFTOCA_UPDATE_GOLDEN=1 if the change is intended
      - \(missing.joined(separator: "\n- "))
      + \(unexpected.joined(separator: "\n+ "))
      """
    )
  }

  // MARK: - probing

  private struct Probe {
    let name: String
    let protocolOfController: OcaControlProtocol
    let lock: OcaLockState
  }

  private static let probes = [
    Probe(name: "ocp1", protocolOfController: .ocp1, lock: .noLock),
    Probe(name: "ocp2", protocolOfController: .ocp2, lock: .noLock),
    Probe(name: "ocp1ReadLocked", protocolOfController: .ocp1, lock: .lockNoReadWrite),
    Probe(name: "ocp2ReadLocked", protocolOfController: .ocp2, lock: .lockNoReadWrite),
    Probe(name: "ocp1WriteLocked", protocolOfController: .ocp1, lock: .lockNoWrite),
    Probe(name: "ocp2WriteLocked", protocolOfController: .ocp2, lock: .lockNoWrite),
  ]

  @OcaDevice
  private static func probeEverything() async throws -> [String] {
    let literalIDs = try methodIDLiterals()
    let classes = OcaDeviceClassRegistry.shared.registeredClasses
      .map { ($0.key, $0.value) }
      .sorted { a, b in
        let (x, y) = (a.0.classID.description, b.0.classID.description)
        if x == y { return a.0.classVersion < b.0.classVersion }
        return x.localizedStandardCompare(y) == .orderedAscending
      }

    var lines = [String]()
    for (identification, type) in classes {
      let name = String(describing: type)
      let prefix = "{\"class\":\"\(name)\",\"classID\":\"\(identification.classID)\""
      let object: SwiftOCADevice.OcaRoot
      let device = try await freshDevice()
      do {
        object = try await makeObject(type, device: device)
      } catch {
        lines.append("\(prefix),\"skipped\":\"\(error)\"}")
        continue
      }

      var methodIDs = literalIDs
      for property in object.devicePropertyDescriptors {
        for id in [property.getMethodID, property.setMethodID].compactMap({ $0 }) {
          methodIDs.insert(id)
        }
      }
      for method in type.deviceMethods {
        methodIDs.insert(method.methodID)
      }

      for methodID in methodIDs.sorted(by: { ($0.defLevel, $0.methodIndex) < ($1.defLevel, $1.methodIndex) }) {
        var statuses = [String]()
        for probe in probes {
          // a fresh object for each, as a probe may change the object it hits
          let object = try await makeObject(type, device: device)
          statuses.append(await status(of: object, methodID, probe))
        }
        guard statuses.contains(where: { $0 != "notImplemented" }) else { continue }
        let fields = zip(probes, statuses).map { "\"\($0.name)\":\"\($1)\"" }
        lines.append("\(prefix),\"method\":\"\(methodID)\",\(fields.joined(separator: ","))}")
      }
    }
    return lines
  }

  @OcaDevice
  private static func status(of object: SwiftOCADevice.OcaRoot, _ methodID: OcaMethodID, _ probe: Probe) async
    -> String
  {
    let holder = ProbeController(protocol: .ocp1)
    do {
      switch probe.lock {
      case .noLock: break
      case .lockNoWrite: try await object.setLockNoWrite(from: holder)
      case .lockNoReadWrite: try await object.setLockNoReadWrite(from: holder)
      }
    } catch {
      return "lockFailed:\(error)"
    }

    let parameters: OcaParameters = probe.protocolOfController == .ocp1
      ? OcaParameters()
      : OcaParameters(ocp2Parameters: [:])
    let command = Ocp1Command(
      handle: 1,
      targetONo: object.objectNumber,
      methodID: methodID,
      parameters: parameters
    )
    do {
      let response = try await object.handleCommand(
        command,
        from: ProbeController(protocol: probe.protocolOfController)
      )
      return "\(response.statusCode)"
    } catch let Ocp1Error.status(status) {
      return "\(status)"
    } catch let error as Ocp1Error {
      return "Ocp1Error.\(error)"
    } catch {
      return "\(type(of: error))"
    }
  }

  @OcaDevice
  private static func freshDevice() async throws -> OcaDevice {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await SwiftOCADevice.OcaClassManager(deviceDelegate: device)
    return device
  }

  /// Classes whose required initialiser is unsupported take their own.
  @OcaDevice
  private static func makeObject(_ type: SwiftOCADevice.OcaRoot.Type, device: OcaDevice) async throws -> SwiftOCADevice.OcaRoot {
    switch type {
    case is SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaWorker>.Type:
      return try await SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaWorker>(
        rows: 2, columns: 2, deviceDelegate: device, addToRootBlock: false
      )
    case is SwiftOCADevice.OcaInt8Sensor.Type:
      return try await SwiftOCADevice.OcaInt8Sensor(.init(value: 0, in: -1...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaInt16Sensor.Type:
      return try await SwiftOCADevice.OcaInt16Sensor(.init(value: 0, in: -1...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaInt32Sensor.Type:
      return try await SwiftOCADevice.OcaInt32Sensor(.init(value: 0, in: -1...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaInt64Sensor.Type:
      return try await SwiftOCADevice.OcaInt64Sensor(.init(value: 0, in: -1...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaUint8Sensor.Type:
      return try await SwiftOCADevice.OcaUint8Sensor(.init(value: 0, in: 0...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaUint16Sensor.Type:
      return try await SwiftOCADevice.OcaUint16Sensor(.init(value: 0, in: 0...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaUint32Sensor.Type:
      return try await SwiftOCADevice.OcaUint32Sensor(.init(value: 0, in: 0...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaUint64Sensor.Type:
      return try await SwiftOCADevice.OcaUint64Sensor(.init(value: 0, in: 0...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaFloat32Sensor.Type:
      return try await SwiftOCADevice.OcaFloat32Sensor(.init(value: 0, in: -1...1), deviceDelegate: device, addToRootBlock: false)
    case is SwiftOCADevice.OcaFloat64Sensor.Type:
      return try await SwiftOCADevice.OcaFloat64Sensor(.init(value: 0, in: -1...1), deviceDelegate: device, addToRootBlock: false)
    default:
      return try await type.init(
        objectNumber: nil,
        lockable: true,
        role: "Probe",
        deviceDelegate: device,
        addToRootBlock: false
      )
    }
  }

  /// Every `OcaMethodID("x.y")` written in SwiftOCADevice's sources.
  private static func methodIDLiterals() throws -> Set<OcaMethodID> {
    let sources = packageRoot.appendingPathComponent("Sources/SwiftOCADevice")
    let regex = try NSRegularExpression(pattern: #"OcaMethodID\("(\d+\.\d+)"\)"#)
    var ids = Set<OcaMethodID>()
    let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
    for case let file as URL in enumerator where file.pathExtension == "swift" {
      let text = try String(contentsOf: file, encoding: .utf8)
      for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        ids.insert(OcaMethodID(String(text[Range(match.range(at: 1), in: text)!])))
      }
    }
    return ids
  }
}

private actor ProbeController: OcaController {
  nonisolated let flags: OcaControllerFlags = [.supportsLocking]
  nonisolated let controlProtocol: OcaControlProtocol

  init(protocol: OcaControlProtocol) {
    controlProtocol = `protocol`
  }

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
}
