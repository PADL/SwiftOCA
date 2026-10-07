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
  "OcaDeviceClass": OcaDeviceClassMacro.self,
]

@Suite struct OcaDeviceMethodMacroTests {
  @Test func severalParametersBecomeARecord() {
    assertMacroExpansion(
      """
      @OcaDeviceClass
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

        static func _ocaDeviceMethod_setPortName(_: (OcaPortID, OcaString).Type) -> OcaDeviceMethodDescriptor {
          OcaDeviceMethodDescriptor(
            OcaMethodID("2.7"),
            name: "SetPortName",
            access: .write,
            parameters: _ocaDeviceMethodParameters_setPortName.self,
            argumentNames: ["id", "name"],
            parameterNames: ["ID", "Name"]
          ) { object, parameters, controller in
            let parameters = parameters as! _ocaDeviceMethodParameters_setPortName
            try (object as! Self).setPortName(parameters.id, parameters.name, from: controller)
            return nil
          }
        }

          override open class var deviceMethods: [OcaDeviceMethodDescriptor] {
            var methods = super.deviceMethods
            methods += [_ocaDeviceMethod_setPortName((OcaPortID, OcaString).self)]
            return methods
          }
      }
      """,
      macros: macros
    )
  }

  /// The test support does not expand a peer inside `#if`; the compiler does.
  @Test func aMethodUnderAConditionIsListedUnderIt() {
    assertMacroExpansion(
      """
      @OcaDeviceClass
      final class Manager: OcaManager {
        @OcaDeviceMethod("3.16", name: "ClearResetCause", access: .write)
        func clearResetCause(from controller: any OcaController) {}
        #if NonEmbeddedBuild
        @OcaDeviceMethod("3.27", name: "ApplyPatch", access: .write)
        func applyPatch(_ oNo: OcaONo, from controller: any OcaController) async throws {}
        #endif
      }
      """,
      expandedSource: """
      final class Manager: OcaManager {
        func clearResetCause(from controller: any OcaController) {}

        static func _ocaDeviceMethod_clearResetCause(_: Void.Type) -> OcaDeviceMethodDescriptor {
          OcaDeviceMethodDescriptor(
            OcaMethodID("3.16"),
            name: "ClearResetCause",
            access: .write
          ) { object, _, controller in
            (object as! Self).clearResetCause(from: controller)
            return nil
          }
        }
        #if NonEmbeddedBuild
        func applyPatch(_ oNo: OcaONo, from controller: any OcaController) async throws {}
        #endif

          override class var deviceMethods: [OcaDeviceMethodDescriptor] {
            var methods = super.deviceMethods
            methods += [_ocaDeviceMethod_clearResetCause(Void.self)]
            #if NonEmbeddedBuild
            methods += [_ocaDeviceMethod_applyPatch(OcaONo.self)]
            #endif
            return methods
          }
      }
      """,
      macros: macros
    )
  }

  @Test func oneParameterAndAResult() {
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

      static func _ocaDeviceMethod_getPortName(_: OcaPortID.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          OcaMethodID("2.6"),
          name: "GetPortName",
          access: .read,
          parameters: OcaPortID.self,
          argumentNames: ["portID"],
          result: OcaString.self,
          resultNames: ["Name"]
        ) { object, parameters, controller in
          try await (object as! Self).getPortName(parameters as! OcaPortID, from: controller)
        }
      }
      """,
      macros: macros
    )
  }

  @Test func noParameters() {
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

      static func _ocaDeviceMethod_getPath(_: Void.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          OcaMethodID("2.13"),
          name: "GetPath",
          access: .read,
          result: OcaGetPathParameters.self
        ) { object, _, controller in
          await (object as! Self).getPath(from: controller)
        }
      }
      """,
      macros: macros
    )
  }

  @Test func theRawFormTakesTheCommand() {
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

      static func _ocaDeviceMethod_applyPatch(_: Ocp1Command.Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          OcaMethodID("3.27"),
          name: "ApplyPatch",
          parameters: OcaApplyPatchParameters.self
        ) { object, command, controller in
          try await (object as! Self).applyPatch(command, from: controller)
        }
      }
      """,
      macros: macros
    )
  }

  @Test func aMethodWithoutAControllerIsRefused() {
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
