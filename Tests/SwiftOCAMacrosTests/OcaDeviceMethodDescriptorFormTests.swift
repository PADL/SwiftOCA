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
]

/// `@OcaDeviceMethod` taking the client's descriptor.
final class OcaDeviceMethodDescriptorFormTests: XCTestCase {
  func testADeviceMethodTakesTheDescriptor() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.setPortName, access: .write)
      func setPortName(_ parameters: SwiftOCA.OcaWorker.SetPortNameParameters, from controller: any OcaController) throws {
        try setName(parameters.name, ofPort: parameters.id)
      }
      """,
      expandedSource: """
      func setPortName(_ parameters: SwiftOCA.OcaWorker.SetPortNameParameters, from controller: any OcaController) throws {
        try setName(parameters.name, ofPort: parameters.id)
      }

      static var _ocaDeviceMethod_setPortName: OcaDeviceMethodDescription {
        OcaDeviceMethodDescription(
          SwiftOCA.OcaWorker.setPortName,
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

  func testADeviceMethodWithNoParametersTakesTheDescriptor() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.getPath, access: .read)
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
          SwiftOCA.OcaWorker.getPath,
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

  func testTheDescriptorFormRefusesNamesAndSeveralParameters() {
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.setPortName, access: .write, parameterNames: ["ID", "Name"])
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
    assertMacroExpansion(
      """
      @OcaDeviceMethod(SwiftOCA.OcaWorker.setPortName, access: .write)
      func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) throws {
      }
      """,
      expandedSource: """
      func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) throws {
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "a method declared by its descriptor takes the descriptor's Parameters as one argument",
          line: 1,
          column: 1
        ),
      ],
      macros: macros
    )
  }
}
