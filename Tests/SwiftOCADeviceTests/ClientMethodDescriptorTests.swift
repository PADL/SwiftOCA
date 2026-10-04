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
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import XCTest

final class ClientMethodDescriptorTests: XCTestCase {
  /// `ClientMethodDescriptors.all` names every `static let x = OcaMethodDescriptor<...>`
  /// in the client sources, found here by reading them.
  func testListsEveryDescriptor() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/SwiftOCA")
    let declared = try Self.declaredDescriptors(under: sources)
    XCTAssertFalse(declared.isEmpty, "no descriptors found under \(sources.path)")
    let listed = Set(ClientMethodDescriptors.all.flatMap { type, descriptors in
      descriptors.map { "\(type).\($0.name)" }
    })
    XCTAssertEqual(declared.subtracting(listed).sorted(), [], "declared but not listed")
    XCTAssertEqual(listed.subtracting(declared).sorted(), [], "listed but not declared")
  }

  /// Every entry of every device class's `deviceMethods` is a client descriptor: the same
  /// ID, name, parameter and result names and types, except the methods named below.
  @OcaDevice
  func testEveryDeviceMethodIsAClientDescriptor() async throws {
    // SetResetKey's key is a 16-tuple, which no descriptor type stands for
    let deviceOnly: Set<String> = ["OcaDeviceManager.3.14"]
    let client = Dictionary(
      uniqueKeysWithValues: ClientMethodDescriptors.all.map { (Self.className($0.type), $0.descriptors) }
    )
    var checked = 0
    var missing = [String]()
    var seen = Set<String>()
    for (_, type) in OcaDeviceClassRegistry.shared.registeredClasses {
      for method in type.deviceMethods {
        // the entry belongs to the class that declares it, which may be a parent
        guard let owner = Self.declaringClass(of: method.methodID, in: type) else { continue }
        let key = "\(Self.className(owner)).\(method.methodID)"
        guard seen.insert(key).inserted else { continue }
        let descriptor = client[Self.className(owner)]?
          .first { $0.descriptor.methodID == method.methodID }?.descriptor
        guard let descriptor else {
          if !deviceOnly.contains(key) { missing.append("\(key) \(method.name)") }
          // the raw method without metadata is the one not described
          XCTAssertFalse(method.isDescribed, key)
          continue
        }
        XCTAssertTrue(method.isDescribed, key)
        checked += 1
        XCTAssertEqual(method.name, descriptor.name, key)
        XCTAssertEqual(method.parameters.map(\.name), descriptor.parameters.map(\.name), key)
        XCTAssertEqual(method.results.map(\.name), descriptor.results.map(\.name), key)
        XCTAssertTrue(
          method.method.parametersType.map(ObjectIdentifier.init) ==
            descriptor.parametersType.map(ObjectIdentifier.init),
          "\(key) parameter type"
        )
        XCTAssertTrue(
          method.method.resultType.map(ObjectIdentifier.init) ==
            descriptor.resultType.map(ObjectIdentifier.init),
          "\(key) result type"
        )
      }
    }
    print("device method sweep: \(checked) entries are client descriptors, \(missing.count) without one")
    for entry in missing.sorted() {
      print("  \(entry)")
    }
    XCTAssertEqual(missing, [], "device methods without a client descriptor")
  }

  /// The type's name without its generic arguments, the same on both sides.
  private static func className(_ type: Any.Type) -> String {
    String(String(describing: type).prefix { $0 != "<" })
  }

  /// The class in `type`'s lineage whose class ID is at the method's definition level.
  @OcaDevice
  private static func declaringClass(
    of methodID: OcaMethodID,
    in type: SwiftOCADevice.OcaRoot.Type
  ) -> SwiftOCADevice.OcaRoot.Type? {
    var current: SwiftOCADevice.OcaRoot.Type? = type
    while let type = current {
      if type.classID.defLevel == methodID.defLevel { return type }
      current = _getSuperclass(type) as? SwiftOCADevice.OcaRoot.Type
    }
    return nil
  }

  /// `Class.name` for each descriptor declaration, the class being the innermost type
  /// declaration enclosing it.
  private static func declaredDescriptors(under directory: URL) throws -> Set<String> {
    var found = Set<String>()
    let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" }
    let typeDecl = try NSRegularExpression(
      pattern: #"^\s*(?:@\w+\s+)*(?:open |public |final |private |fileprivate |package )*(?:class|extension|struct|enum|actor) ([\w.]+)"#
    )
    // the initialiser may start on the next line
    let descriptor = try NSRegularExpression(
      pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public )?static let (\w+)\s*=\s*(.*)$"#
    )
    for file in files {
      var stack = [(depth: Int, name: String)]()
      var depth = 0
      var pending: String?
      let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
      for (index, line) in lines.enumerated() {
        let range = NSRange(line.startIndex..., in: line)
        if !line.trimmingCharacters(in: .whitespaces).hasPrefix("//"),
           let match = typeDecl.firstMatch(in: line, range: range)
        {
          pending = String(line[Range(match.range(at: 1), in: line)!])
        }
        if let name = pending, line.contains("{") {
          stack.append((depth, name))
          pending = nil
        }
        if let match = descriptor.firstMatch(in: line, range: range), let owner = stack.last {
          var initialiser = String(line[Range(match.range(at: 2), in: line)!])
          if initialiser.isEmpty, index + 1 < lines.count {
            initialiser = lines[index + 1].trimmingCharacters(in: .whitespaces)
          }
          if initialiser.hasPrefix("OcaMethodDescriptor<") {
            found.insert("\(owner.name).\(line[Range(match.range(at: 1), in: line)!])")
          }
        }
        depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
        while let last = stack.last, depth <= last.depth {
          stack.removeLast()
        }
      }
    }
    return found
  }
}
#endif
