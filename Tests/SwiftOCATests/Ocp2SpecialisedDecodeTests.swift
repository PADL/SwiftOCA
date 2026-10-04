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
import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
import XCTest

/// Answers every command with the same canned OCP.2 parameters.
private final class CannedOcp2Connection: OcaConnection, @unchecked Sendable {
  nonisolated(unsafe) var parameters: [String: Any] = [:]

  override nonisolated var connectionPrefix: String { "oca/canned" }

  override var isDatagram: Bool { false }

  override var heartbeatTime: Duration { .zero }

  override func read(_ length: Int, awaitingAllRead: Bool) async throws -> Data {
    try await Task.sleep(for: .seconds(3600))
    throw Ocp1Error.notConnected
  }

  override func write(_ data: Data) async throws -> Int {
    let (_, messages) = try OcaControlProtocol.ocp2.decodePdu(data)
    for case let command as Ocp1Command in messages {
      try monitor?.resume(with: Ocp1Response(
        handle: command.handle,
        statusCode: .ok,
        parameters: OcaParameters(ocp2Parameters: parameters)
      ))
    }
    return data.count
  }
}

/// `Ocp2Decoder` casts the value's metatype to a protocol existential, which the
/// optimiser folds once the decoder is specialised for that type (the Swift 6.3 bug
/// behind `erasedCast`). Those specialisations only exist inside SwiftOCA, so each cast
/// is driven through a client property of a type that selects it; calling the decoder
/// from this module would run the unspecialised generic instead.
final class Ocp2SpecialisedDecodeTests: XCTestCase {
  @OcaConnectionActor
  private func makeConnection(answering parameters: [String: Any]) -> CannedOcp2Connection {
    let connection = CannedOcp2Connection(
      options: OcaConnectionOptions(responseTimeout: .seconds(5), controlProtocol: .ocp2)
    )
    connection.parameters = parameters
    connection.monitor = OcaConnection.Monitor(connection, id: 1)
    return connection
  }

  @OcaConnectionActor
  private func object<T: OcaRoot>(
    _: T.Type,
    answering parameters: [String: Any]
  ) -> (CannedOcp2Connection, T) {
    let connection = makeConnection(answering: parameters)
    let object = T(objectNumber: 0x0001_0000)
    connection.add(object: object)
    return (connection, object)
  }

  /// The value a property read settles on, once the fetch its getter started has finished.
  @OcaConnectionActor
  private func settled<Value>(
    _ property: OcaProperty<Value>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws -> OcaProperty<Value>.PropertyValue {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      if case .initial = property.currentValue {
        try await Task.sleep(for: .milliseconds(5))
        continue
      }
      return property.currentValue
    }
    XCTFail("property never left its initial state", file: file, line: line)
    return .initial
  }

  // MARK: ExpressibleByNilLiteral

  @OcaConnectionActor
  func testEmptyParametersDecodeAsNilForAnOptionalString() async throws {
    let (connection, group) = object(OcaGroup.self, answering: [:])
    _ = group.aggregationMode
    let value = try await settled(group.$aggregationMode)
    guard case let .success(mode) = value else {
      return XCTFail("expected a value: \(value)")
    }
    XCTAssertNil(mode)
    _ = connection
  }

  @OcaConnectionActor
  func testEmptyParametersAreAnErrorForAString() async throws {
    let (connection, group) = object(OcaGroup.self, answering: [:])
    _ = group.role
    let value = try await settled(group.$role)
    guard case let .failure(error) = value else {
      return XCTFail("expected an error: \(value)")
    }
    XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    _ = connection
  }

  // MARK: Ocp1BlobRepresentable

  @OcaConnectionActor
  func testBlobDecodesFromBase64() async throws {
    let (connection, interface) = object(OcaNetworkInterface.self, answering: ["Settings": "AQID"])
    _ = interface.currentAdaptationData
    let value = try await settled(interface.$currentAdaptationData)
    guard case let .success(blob) = value else {
      return XCTFail("expected a value: \(value)")
    }
    XCTAssertEqual(blob, OcaBlob(Data([1, 2, 3])))
    _ = connection
  }

  // MARK: Ocp1MapRepresentable

  @OcaConnectionActor
  func testMapDecodesFromPairs() async throws {
    let (connection, manager) = object(
      OcaCodingManager.self,
      answering: ["Schemes": [[1, "PCM"], [2, "AAC"]]]
    )
    _ = manager.availableEncodingSchemes
    let value = try await settled(manager.$availableEncodingSchemes)
    guard case let .success(schemes) = value else {
      return XCTFail("expected a value: \(value)")
    }
    XCTAssertEqual(schemes, [1: "PCM", 2: "AAC"])
    _ = connection
  }

  // MARK: CaseIterable

  @OcaConnectionActor
  func testEnumerationDecodesByCaseName() async throws {
    let (connection, group) = object(OcaGroup.self, answering: ["State": "LockNoWrite"])
    _ = group.lockState
    let value = try await settled(group.$lockState)
    guard case let .success(state) = value else {
      return XCTFail("expected a value: \(value)")
    }
    XCTAssertEqual(state, .lockNoWrite)
    _ = connection
  }
}
#endif
