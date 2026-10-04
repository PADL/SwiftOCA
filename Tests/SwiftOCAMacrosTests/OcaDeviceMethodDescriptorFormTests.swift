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

import SwiftOCAMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: any Macro.Type] = [
  "OcaDeviceMethod": OcaDeviceMethodMacro.self,
]

/// `@OcaDeviceMethod` taking the client's descriptor.
@Suite struct OcaDeviceMethodDescriptorFormTests {
  @Test func aDeviceMethodTakesTheDescriptorsParametersAsArguments() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.Methods.setPortName, access: .write)
      open func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) throws {
        try setName(name, ofPort: id)
      }
      """,
      expandedSource: """
      open func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) throws {
        try setName(name, ofPort: id)
      }

      static func _ocaDeviceMethod_setPortName(_: (OcaPortID, OcaString).Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          SwiftOCA.OcaWorker.Methods.setPortName,
          access: .write,
          result: Void.self
        ) { object, parameters, controller in
          let parameters = SwiftOCA.OcaWorker.Methods.setPortName.parameters(parameters)
          try (object as! Self).setPortName(parameters.id, parameters.name, from: controller)
          return nil
        }
      }
      """,
      macros: macros
    )
  }

  @Test func aDeviceMethodMayTakeTheRecord() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.Methods.setPortName, access: .write)
      func setPortName(_ parameters: SwiftOCA.OcaWorker.SetPortNameParameters, from controller: any OcaController) throws {
        try setName(parameters.name, ofPort: parameters.id)
      }
      """,
      expandedSource: """
      func setPortName(_ parameters: SwiftOCA.OcaWorker.SetPortNameParameters, from controller: any OcaController) throws {
        try setName(parameters.name, ofPort: parameters.id)
      }

      static func _ocaDeviceMethod_setPortName(_: SwiftOCA.OcaWorker.SetPortNameParameters.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          SwiftOCA.OcaWorker.Methods.setPortName,
          access: .write,
          parameters: SwiftOCA.OcaWorker.SetPortNameParameters.self,
          result: Void.self
        ) { object, parameters, controller in
          try (object as! Self).setPortName(parameters as! SwiftOCA.OcaWorker.SetPortNameParameters, from: controller)
          return nil
        }
      }
      """,
      macros: macros
    )
  }

  @Test func aDeviceMethodWithNoParametersTakesTheDescriptor() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.Methods.getPath, access: .read)
      func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
        await path
      }
      """,
      expandedSource: """
      func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
        await path
      }

      static func _ocaDeviceMethod_getPath(_: Void.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          SwiftOCA.OcaWorker.Methods.getPath,
          access: .read,
          parameters: Void.self,
          result: OcaGetPathParameters.self
        ) { object, _, controller in
          await (object as! Self).getPath(from: controller)
        }
      }
      """,
      macros: macros
    )
  }

  /// Two hooks sharing a Swift name get two descriptors, told apart by their arguments.
  @Test func overloadedHooksGetDistinctDescriptors() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(Parameters.setEndpointUserLabel, access: .write)
      open func setEndpoint(_ endpointID: OcaMediaStreamEndpointID, userLabel label: OcaString, from controller: any OcaController) async throws {
      }
      """,
      expandedSource: """
      open func setEndpoint(_ endpointID: OcaMediaStreamEndpointID, userLabel label: OcaString, from controller: any OcaController) async throws {
      }

      static func _ocaDeviceMethod_setEndpoint(_: (OcaMediaStreamEndpointID, userLabel: OcaString).Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          Parameters.setEndpointUserLabel,
          access: .write,
          result: Void.self
        ) { object, parameters, controller in
          let parameters = Parameters.setEndpointUserLabel.parameters(parameters)
          try await (object as! Self).setEndpoint(parameters.endpointID, userLabel: parameters.label, from: controller)
          return nil
        }
      }
      """,
      macros: macros
    )
  }

  @Test func accessFollowsTheMethodsNameUnlessStated() {
    // a getter reads
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.Methods.getPath)
      func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
        await path
      }
      """,
      expandedSource: """
      func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
        await path
      }

      static func _ocaDeviceMethod_getPath(_: Void.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          SwiftOCA.OcaWorker.Methods.getPath,
          access: .read,
          parameters: Void.self,
          result: OcaGetPathParameters.self
        ) { object, _, controller in
          await (object as! Self).getPath(from: controller)
        }
      }
      """,
      macros: macros
    )
    // a mutator writes
    assertMacroExpansion(
      """
      @OcaDeviceMethod(Parameters.deleteSession)
      open func delete(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
      }
      """,
      expandedSource: """
      open func delete(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
      }

      static func _ocaDeviceMethod_delete(_: OcaMediaTransportSessionID.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          Parameters.deleteSession,
          access: .write,
          parameters: OcaMediaTransportSessionID.self,
          result: Void.self
        ) { object, parameters, controller in
          try await (object as! Self).delete(session: parameters as! OcaMediaTransportSessionID, from: controller)
          return nil
        }
      }
      """,
      macros: macros
    )
    // written .inferred, it is the default
    assertMacroExpansion(
      """
      @OcaDeviceMethod(Parameters.deleteSession, access: .inferred)
      open func delete(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
      }
      """,
      expandedSource: """
      open func delete(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
      }

      static func _ocaDeviceMethod_delete(_: OcaMediaTransportSessionID.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          Parameters.deleteSession,
          access: .write,
          parameters: OcaMediaTransportSessionID.self,
          result: Void.self
        ) { object, parameters, controller in
          try await (object as! Self).delete(session: parameters as! OcaMediaTransportSessionID, from: controller)
          return nil
        }
      }
      """,
      macros: macros
    )
    // stated, it overrides the name: .unchecked on a getter
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaRoot.Methods.getLockState, access: .unchecked)
      func getLockState(from controller: any OcaController) -> OcaLockState {
        lockState.lockState
      }
      """,
      expandedSource: """
      func getLockState(from controller: any OcaController) -> OcaLockState {
        lockState.lockState
      }

      static func _ocaDeviceMethod_getLockState(_: Void.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          SwiftOCA.OcaRoot.Methods.getLockState,
          access: .unchecked,
          parameters: Void.self,
          result: OcaLockState.self
        ) { object, _, controller in
          (object as! Self).getLockState(from: controller)
        }
      }
      """,
      macros: macros
    )
    // stated, it overrides the name: .read on a name that would write
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaDataset.Methods.openRead, access: .read)
      func openRead(_ lockState: OcaLockState, from controller: any OcaController) async throws -> OpenReadParameters {
      }
      """,
      expandedSource: """
      func openRead(_ lockState: OcaLockState, from controller: any OcaController) async throws -> OpenReadParameters {
      }

      static func _ocaDeviceMethod_openRead(_: OcaLockState.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          SwiftOCA.OcaDataset.Methods.openRead,
          access: .read,
          parameters: OcaLockState.self,
          result: OpenReadParameters.self
        ) { object, parameters, controller in
          try await (object as! Self).openRead(parameters as! OcaLockState, from: controller)
        }
      }
      """,
      macros: macros
    )
    // a name that says neither must state it
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaLockManager.Methods.lockWait)
      private func lockWait(controller: OcaController, target: OcaONo, type: OcaLockState, timeout: OcaTimeInterval) async throws {
      }
      """,
      expandedSource: """
      private func lockWait(controller: OcaController, target: OcaONo, type: OcaLockState, timeout: OcaTimeInterval) async throws {
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@OcaDeviceMethod cannot tell whether 'lockWait' reads or writes; state access: .read, .write or .unchecked",
          line: 1,
          column: 1
        ),
      ],
      macros: macros
    )
  }

  @Test func theDescriptorFormRefusesNames() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.Methods.setPortName, access: .write, parameterNames: ["ID", "Name"])
      func setPortName(_ parameters: SwiftOCA.OcaWorker.SetPortNameParameters, from controller: any OcaController) throws {
      }
      """,
      expandedSource: """
      func setPortName(_ parameters: SwiftOCA.OcaWorker.SetPortNameParameters, from controller: any OcaController) throws {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "the descriptor gives the method its parameterNames", line: 1, column: 1),
      ],
      macros: macros
    )
  }
}
