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

private actor TestController: OcaController {
  nonisolated let flags: OcaControllerFlags = [.supportsLocking]

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
}

/// A subclass whose own arm answers a method its parent declares with `@OcaDeviceMethod`,
/// as InfernoDevice's classes do for the methods they wrap.
private final class _ArmedWorker: SwiftOCADevice.OcaWorker {
  override func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.13"):
      throw Ocp1Error.status(.notImplemented)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

final class DeviceMethodTests: XCTestCase {
  @OcaDevice
  private func makeWorker<T: SwiftOCADevice.OcaWorker>(_ type: T.Type = T.self) async throws
    -> T
  {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let worker = try await T(role: "Worker", deviceDelegate: device)
    worker.ports = [
      OcaPort(owner: worker.objectNumber, id: OcaPortID(mode: .input, index: 1), name: "In 1"),
    ]
    return worker
  }

  private func command<T: Encodable>(
    _ methodID: OcaMethodID,
    _ parameters: T,
    on object: SwiftOCADevice.OcaRoot
  ) throws -> Ocp1Command {
    try Ocp1Command(
      handle: 1,
      targetONo: object.objectNumber,
      methodID: methodID,
      parameters: OcaParameters(
        parameterCount: _ocp1ParameterCount(type: T.self),
        parameterData: Ocp1Encoder().encode(parameters)
      )
    )
  }

  @OcaDevice
  func testATableMethodAnswersACommand() async throws {
    let worker: SwiftOCADevice.OcaWorker = try await makeWorker()
    let controller = TestController()

    let set = try command(
      OcaMethodID("2.7"),
      SwiftOCA.OcaWorker.SetPortNameParameters(id: OcaPortID(mode: .input, index: 1), name: "Mic"),
      on: worker
    )
    let setResponse = try await worker.handleCommand(set, from: controller)
    XCTAssertEqual(setResponse.statusCode, .ok)
    XCTAssertEqual(worker.ports.first?.name, "Mic")

    let get = try command(OcaMethodID("2.6"), OcaPortID(mode: .input, index: 1), on: worker)
    let getResponse = try await worker.handleCommand(get, from: controller)
    XCTAssertEqual(getResponse.parameters.parameterCount, 1)
    let name = try Ocp1Decoder().decode(OcaString.self, from: getResponse.parameters.parameterData)
    XCTAssertEqual(name, "Mic")

    let path = try command(OcaMethodID("2.13"), SwiftOCA.OcaRoot.Placeholder(), on: worker)
    let pathResponse = try await worker.handleCommand(path, from: controller)
    XCTAssertEqual(pathResponse.parameters.parameterCount, 2)
  }

  @OcaDevice
  func testAWrongParameterCountIsRefused() async throws {
    let worker: SwiftOCADevice.OcaWorker = try await makeWorker()
    // two parameters where GetPortName takes one
    let get = try command(
      OcaMethodID("2.6"),
      SwiftOCA.OcaWorker.SetPortNameParameters(id: OcaPortID(mode: .input, index: 1), name: "Mic"),
      on: worker
    )
    do {
      _ = try await worker.handleCommand(get, from: TestController())
      XCTFail("decoded a GetPortName with two parameters")
    } catch Ocp1Error.status(.parameterOutOfRange) {}
  }

  @OcaDevice
  func testAMissingParameterIsOutOfRangeNotADeviceError() async throws {
    let worker: SwiftOCADevice.OcaWorker = try await makeWorker()
    let get = Ocp1Command(
      handle: 1,
      targetONo: worker.objectNumber,
      methodID: OcaMethodID("2.6"),
      parameters: OcaParameters(parameterCount: 0, parameterData: Data())
    )
    do {
      _ = try await worker.handleCommand(get, from: TestController())
      XCTFail("decoded a GetPortName with no parameter")
    } catch Ocp1Error.status(.parameterOutOfRange) {}
  }

  @OcaDevice
  func testATruncatedParameterIsBadFormat() async throws {
    let worker: SwiftOCADevice.OcaWorker = try await makeWorker()
    // one parameter, but one byte of an OcaPortID
    let get = Ocp1Command(
      handle: 1,
      targetONo: worker.objectNumber,
      methodID: OcaMethodID("2.6"),
      parameters: OcaParameters(parameterCount: 1, parameterData: Data([0x01]))
    )
    do {
      _ = try await worker.handleCommand(get, from: TestController())
      XCTFail("decoded a truncated GetPortName")
    } catch Ocp1Error.status(.badFormat) {}
  }

  @OcaDevice
  func testABlockWithoutDatasetStorageHasNoDatasets() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let block = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      role: "Block",
      deviceDelegate: device
    )
    let controller = TestController()

    for methodID in [OcaMethodID("3.29"), OcaMethodID("3.30")] {
      let get = Ocp1Command(
        handle: 1,
        targetONo: block.objectNumber,
        methodID: methodID,
        parameters: OcaParameters()
      )
      let response = try await block.handleCommand(get, from: controller)
      XCTAssertEqual(response.statusCode, .ok)
      XCTAssertEqual(response.parameters.parameterCount, 1)
      let count = try Ocp1Decoder().decode(OcaUint16.self, from: response.parameters.parameterData)
      XCTAssertEqual(count, 0)
    }

    // what needs storage to do anything is not implemented, and not a device error
    let apply = try command(OcaMethodID("3.23"), OcaONo(0x1000_0000), on: block)
    let response = await device.handleCommand(apply, from: controller)
    XCTAssertEqual(response.statusCode, .notImplemented)
  }

  @OcaDevice
  func testASubclassArmTakesPrecedence() async throws {
    let worker: _ArmedWorker = try await makeWorker()
    let path = try command(OcaMethodID("2.13"), SwiftOCA.OcaRoot.Placeholder(), on: worker)
    do {
      _ = try await worker.handleCommand(path, from: TestController())
      XCTFail("the table answered a method the subclass declined")
    } catch Ocp1Error.status(.notImplemented) {}
  }

  @OcaDevice
  func testTheMethodsAreDescribed() async throws {
    let worker: SwiftOCADevice.OcaWorker = try await makeWorker()
    let methods = worker.deviceMethodDescriptors
    XCTAssertEqual(
      methods.map(\.methodID),
      ["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.6", "2.7", "2.13", "2.16", "2.17", "2.18"]
    )

    let setPortName = try XCTUnwrap(methods.first { $0.name == "SetPortName" })
    XCTAssertEqual(setPortName.parameters.map(\.name), ["ID", "Name"])
    XCTAssertTrue(setPortName.parameters[0].type == OcaPortID.self)
    XCTAssertTrue(setPortName.parameters[1].type == OcaString.self)
    XCTAssertTrue(setPortName.results.isEmpty)

    let getPortName = try XCTUnwrap(methods.first { $0.name == "GetPortName" })
    XCTAssertEqual(getPortName.parameters.map(\.name), ["PortID"])
    XCTAssertEqual(getPortName.results.map(\.name), ["Name"])
    XCTAssertTrue(getPortName.results[0].type == OcaString.self)

    let getPath = try XCTUnwrap(methods.first { $0.name == "GetPath" })
    XCTAssertTrue(getPath.parameters.isEmpty)
    XCTAssertEqual(getPath.results.map(\.name), ["RolePath", "ONoPath"])

    // listed with the class that defines them, beside its properties
    let classes = worker.deviceClassDescriptors
    XCTAssertEqual(
      classes.last?.methods.prefix(3).map(\.name),
      ["GetPortName", "SetPortName", "GetPath"]
    )
    XCTAssertEqual(classes.first?.methods.first?.name, "GetClassIdentification")
  }
}
