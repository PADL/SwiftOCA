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
  "OcaMethod": OcaMethodMacro.self,
  "OcaMethodDescriptor": OcaMethodDescriptorMacro.self,
  "OcaClass": OcaClassMacro.self,
]

@Suite struct OcaMethodMacroTests {
  @Test func bodiesInvokeTheDescriptor() {
    assertMacroExpansion(
      """
      @OcaClass
      open class OcaWorker: OcaRoot {
        @OcaMethod("2.13", name: "GetPath")
        public func getPath() async throws -> OcaGetPathParameters

        @OcaMethod("2.4", name: "DeletePort", parameterNames: ["ID"])
        public func deletePort(id: OcaPortID) async throws

        @OcaMethod("2.7", name: "SetPortName", parameters: SetPortNameParameters.self, parameterNames: ["ID", "Name"])
        public func setPortName(id: OcaPortID, name: OcaString) async throws
      }
      """,
      expandedSource: """
      open class OcaWorker: OcaRoot {
        public func getPath() async throws -> OcaGetPathParameters {
            try await invoke(Methods.getPath)
        }
        public func deletePort(id: OcaPortID) async throws {
            try await invoke(Methods.deletePort, id)
        }
        public func setPortName(id: OcaPortID, name: OcaString) async throws {
            try await invoke(Methods.setPortName, .init(id: id, name: name))
        }

          /// The descriptors of the class's methods, each under the method's name.
          public enum Methods {
            public static let getPath =
              OcaMethodDescriptor<Void, OcaGetPathParameters>("2.13", name: "GetPath")
            public static let deletePort =
              OcaMethodDescriptor<OcaPortID, Void>("2.4", name: "DeletePort", parameterNames: ["ID"])
            public static let setPortName =
              OcaMethodDescriptor<SetPortNameParameters, Void>("2.7", name: "SetPortName", parameterNames: ["ID", "Name"])
          }
      }
      """,
      macros: macros
    )
  }

  @Test func severalParametersWithoutARecordGetOne() {
    assertMacroExpansion(
      """
      @OcaClass
      public class Vendor: OcaAgent {
        @OcaMethod("3.1", name: "SetRoute", resultNames: ["Previous"])
        public func setRoute(input: OcaUint16, output: OcaUint16) async throws -> OcaUint16
      }
      """,
      expandedSource: """
      public class Vendor: OcaAgent {
        public func setRoute(input: OcaUint16, output: OcaUint16) async throws -> OcaUint16 {
            try await invoke(Methods.setRoute, .init(input: input, output: output))
        }

          /// The descriptors of the class's methods, each under the method's name.
          public enum Methods {
            public struct SetRouteParameters: OcaParametersReflectable {
              public let input: OcaUint16
              public let output: OcaUint16

              public init(input: OcaUint16, output: OcaUint16) {
                self.input = input
                self.output = output
              }
            }
            public static let setRoute =
              OcaMethodDescriptor<SetRouteParameters, OcaUint16>("3.1", name: "SetRoute", resultNames: ["Previous"])
          }
      }
      """,
      macros: macros
    )
  }

  @Test func aHandWrittenBodyDeclaresItsDescriptor() {
    assertMacroExpansion(
      """
      @OcaClass
      final class Filter: OcaActuator {
        @OcaMethodDescriptor("4.2", name: "SetTransferFunction", parameters: SetTransferFunctionParameters.self)
        func setTransferFunction(frequency: [OcaFrequency]) async throws {
          try await invoke(Methods.setTransferFunction, .init(OcaTransferFunction(frequency: frequency)))
        }

        @OcaMethodDescriptor("3.17", name: "Find", result: [OcaObjectSearchResult].self)
        func find(name: OcaString) async throws -> OcaList<OcaObjectSearchResult> {
          try await search(Methods.find, name)
        }
      }
      """,
      expandedSource: """
      final class Filter: OcaActuator {
        func setTransferFunction(frequency: [OcaFrequency]) async throws {
          try await invoke(Methods.setTransferFunction, .init(OcaTransferFunction(frequency: frequency)))
        }
        func find(name: OcaString) async throws -> OcaList<OcaObjectSearchResult> {
          try await search(Methods.find, name)
        }

          /// The descriptors of the class's methods, each under the method's name.
          enum Methods {
            static let setTransferFunction =
              OcaMethodDescriptor<SetTransferFunctionParameters, Void>("4.2", name: "SetTransferFunction")
            static let find =
              OcaMethodDescriptor<OcaString, [OcaObjectSearchResult]>("3.17", name: "Find")
          }
      }
      """,
      macros: macros
    )
  }

  @Test func aMethodUnderAConditionIsDeclaredUnderIt() {
    assertMacroExpansion(
      """
      @OcaClass
      open class Manager: OcaManager {
        @OcaMethod("3.1", name: "Reset")
        public func reset() async throws
        #if NonEmbeddedBuild
        @OcaMethod("3.2", name: "ApplyPatch", parameterNames: ["ONo"])
        public func applyPatch(oNo: OcaONo) async throws
        #endif
      }
      """,
      expandedSource: """
      open class Manager: OcaManager {
        public func reset() async throws {
            try await invoke(Methods.reset)
        }
        #if NonEmbeddedBuild
        public func applyPatch(oNo: OcaONo) async throws {
            try await invoke(Methods.applyPatch, oNo)
        }
        #endif

          /// The descriptors of the class's methods, each under the method's name.
          public enum Methods {
            public static let reset =
              OcaMethodDescriptor<Void, Void>("3.1", name: "Reset")
            #if NonEmbeddedBuild
            public static let applyPatch =
              OcaMethodDescriptor<OcaONo, Void>("3.2", name: "ApplyPatch", parameterNames: ["ONo"])
            #endif
          }
      }
      """,
      macros: macros
    )
  }

  @Test func refusesAMethodWithABody() {
    assertMacroExpansion(
      """
      @OcaMethod("2.4", name: "DeletePort")
      func deletePort(id: OcaPortID) async throws {
        try await invoke(Methods.deletePort, id)
      }
      """,
      expandedSource: """
      func deletePort(id: OcaPortID) async throws {
        try await invoke(Methods.deletePort, id)
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@OcaMethod writes the method's body; leave it out, or declare a hand-written method with @OcaMethodDescriptor",
          line: 1,
          column: 1
        ),
      ],
      macros: macros
    )
  }

  @Test func refusesAMethodThatIsNotAsyncThrows() {
    assertMacroExpansion(
      """
      @OcaMethod("2.4", name: "DeletePort")
      func deletePort(id: OcaPortID) throws
      """,
      expandedSource: """
      func deletePort(id: OcaPortID) throws
      """,
      diagnostics: [
        DiagnosticSpec(message: "an @OcaMethod method is 'async throws'", line: 1, column: 1),
      ],
      macros: macros
    )
  }

  @Test func refusesAnInoutParameter() {
    assertMacroExpansion(
      """
      @OcaMethod("2.4", name: "DeletePort")
      func deletePort(id: inout OcaPortID) async throws
      """,
      expandedSource: """
      func deletePort(id: inout OcaPortID) async throws
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "an OCA method's parameters are plain values, not variadic or inout",
          line: 1,
          column: 1
        ),
      ],
      macros: macros
    )
  }

  @Test func refusesADescriptorWithoutABody() {
    assertMacroExpansion(
      """
      @OcaMethodDescriptor("2.4", name: "DeletePort")
      func deletePort(id: OcaPortID) async throws
      """,
      expandedSource: """
      func deletePort(id: OcaPortID) async throws
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "a method without a body takes @OcaMethod, which writes it",
          line: 1,
          column: 1
        ),
      ],
      macros: macros
    )
  }

  @Test func refusesTwoMethodsOfOneName() {
    assertMacroExpansion(
      """
      @OcaClass
      class Worker: OcaRoot {
        @OcaMethod("2.6", name: "GetPortName")
        func get(portID: OcaPortID) async throws -> OcaString
        @OcaMethod("2.16", name: "GetPortClockMapEntry")
        func get(portID: OcaPortID) async throws -> OcaPortClockMapEntry
      }
      """,
      expandedSource: """
      class Worker: OcaRoot {
        func get(portID: OcaPortID) async throws -> OcaString {
            try await invoke(Methods.get, portID)
        }
        func get(portID: OcaPortID) async throws -> OcaPortClockMapEntry {
            try await invoke(Methods.get, portID)
        }
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "two methods are named 'get'; each OCA method needs its own name",
          line: 1,
          column: 1
        ),
      ],
      macros: macros
    )
  }

  @Test func refusesAnythingButAClass() {
    assertMacroExpansion(
      """
      @OcaClass
      struct Worker {}
      """,
      expandedSource: """
      struct Worker {}
      """,
      diagnostics: [
        DiagnosticSpec(message: "@OcaClass can only be applied to a class", line: 1, column: 1),
      ],
      macros: macros
    )
  }
}
