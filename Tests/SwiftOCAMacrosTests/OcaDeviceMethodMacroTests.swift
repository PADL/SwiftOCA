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
import SwiftSyntaxMacrosTestSupport
import XCTest

private let macros: [String: any Macro.Type] = [
  "OcaDeviceMethod": OcaDeviceMethodMacro.self,
  "OcaDeviceMethods": OcaDeviceMethodsMacro.self,
]

final class OcaDeviceMethodMacroTests: XCTestCase {
  func testSeveralParametersBecomeARecord() {
    assertMacroExpansion(
      """
      @OcaDeviceMethods
      open class OcaWorker: OcaRoot {
        @OcaDeviceMethod("2.7", name: "SetPortName", access: .write, parameterNames: ["ID", "Name"])
        func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) throws {
          try setName(name, ofPort: id)
        }
      }
      """,
      expandedSource: """
      open class OcaWorker: OcaRoot {
        func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) throws {
          try setName(name, ofPort: id)
        }

        struct _ocaDeviceMethodParameters_setPortName: OcaParametersReflectable, Sendable {
          let id: OcaPortID
          let name: OcaString
        }

        static var _ocaDeviceMethod_setPortName: OcaDeviceMethodDescription {
          OcaDeviceMethodDescription(
            OcaMethodID("2.7"),
            name: "SetPortName",
            access: .write,
            parameters: _ocaDeviceMethodParameters_setPortName.self,
            argumentNames: ["id", "name"],
            parameterNames: ["ID", "Name"]
          ) { (object: Self, parameters: _ocaDeviceMethodParameters_setPortName, controller: any OcaController) -> Void in
            try object.setPortName(parameters.id, parameters.name, from: controller)
          }
        }

          override open class var deviceMethods: [OcaDeviceMethodDescription] {
            super.deviceMethods + [_ocaDeviceMethod_setPortName]
          }
      }
      """,
      macros: macros
    )
  }

  func testOneParameterAndAResult() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod("2.6", name: "GetPortName", access: .read, resultNames: ["Name"])
      func getPortName(_ portID: OcaPortID, from controller: any OcaController) async throws -> OcaString {
        try portName(of: portID)
      }
      """,
      expandedSource: """
      func getPortName(_ portID: OcaPortID, from controller: any OcaController) async throws -> OcaString {
        try portName(of: portID)
      }

      static var _ocaDeviceMethod_getPortName: OcaDeviceMethodDescription {
        OcaDeviceMethodDescription(
          OcaMethodID("2.6"),
          name: "GetPortName",
          access: .read,
          parameters: OcaPortID.self,
          argumentNames: ["portID"],
          resultNames: ["Name"]
        ) { (object: Self, parameters: OcaPortID, controller: any OcaController) -> OcaString in
          try await object.getPortName(parameters, from: controller)
        }
      }
      """,
      macros: macros
    )
  }

  func testNoParameters() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod("2.13", name: "GetPath", access: .read)
      func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
        await path
      }
      """,
      expandedSource: """
      func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
        await path
      }

      static var _ocaDeviceMethod_getPath: OcaDeviceMethodDescription {
        OcaDeviceMethodDescription(
          OcaMethodID("2.13"),
          name: "GetPath",
          access: .read
        ) { (object: Self, controller: any OcaController) -> OcaGetPathParameters in
          await object.getPath(from: controller)
        }
      }
      """,
      macros: macros
    )
  }

  func testTheRawFormTakesTheCommand() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod("3.27", name: "ApplyPatch", parameters: OcaApplyPatchParameters.self)
      func applyPatch(_ command: Ocp1Command, from controller: any OcaController) async throws -> Ocp1Response {
        Ocp1Response()
      }
      """,
      expandedSource: """
      func applyPatch(_ command: Ocp1Command, from controller: any OcaController) async throws -> Ocp1Response {
        Ocp1Response()
      }

      static var _ocaDeviceMethod_applyPatch: OcaDeviceMethodDescription {
        OcaDeviceMethodDescription(
          OcaMethodID("3.27"),
          name: "ApplyPatch",
          parameters: OcaApplyPatchParameters.self
        ) { (object: Self, command: Ocp1Command, controller: any OcaController) -> Ocp1Response in
          try await object.applyPatch(command, from: controller)
        }
      }
      """,
      macros: macros
    )
  }

  func testAMethodWithoutAControllerIsRefused() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod("2.6", name: "GetPortName", access: .read)
      func getPortName(_ portID: OcaPortID) throws -> OcaString { "" }
      """,
      expandedSource: """
      func getPortName(_ portID: OcaPortID) throws -> OcaString { "" }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "an @OcaDeviceMethod method takes the controller, as `from controller: any OcaController`",
          line: 1,
          column: 1
        ),
      ],
      macros: macros
    )
  }
}
