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

/// Compares the OCP.2 accessor names SwiftOCA derives from its Swift property names
/// against the normative AES70-2 class model (the XMI that defines AES70-2A).
///
/// Names are judged by the rule the wire uses, so a difference of capitalisation
/// alone is not a deviation: SwiftOCA upper-cases the first letter on send and
/// `Ocp2Naming.matches` folds case on receipt, and the model itself spells 32 of its
/// parameter names both ways (`Gain`/`gain`, `Label`/`label`). What is left is the
/// names no derivation recovers, which need an `ocp2Name:` on the property wrapper.
///
/// Informational: it prints every deviation and fails only if the model cannot be
/// read. Point `AES70_2_XMI` at `AES70-2-2023-231218.xmi` (or a later revision) to
/// run it; it is skipped otherwise.
final class Ocp2NamingOracleTests: XCTestCase {
  private struct Method {
    let classID: String
    let className: String
    let methodID: String
    let name: String
    let inputs: [String]
    let outputs: [String]
  }

  /// A minimal scrape of the Enterprise Architect XMI: operations, their element IDs
  /// (`<style value="04m01">`) and parameter names.
  private static func loadModel(from url: URL) throws -> [Method] {
    let text = try String(contentsOf: url, encoding: .windowsCP1252)

    func matches(_ pattern: String, in string: String, options: NSRegularExpression.Options = []) -> [[String]] {
      let regex = try! NSRegularExpression(pattern: pattern, options: options)
      return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).map { match in
        (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: string).map { String(string[$0]) } ?? "" }
      }
    }

    var methodIDs = [String: String]()
    for m in matches("<operation xmi:idref=\"([^\"]+)\"[^>]*>.*?<style value=\"([^\"]*)\"", in: text, options: [.dotMatchesLineSeparators]) {
      let style = m[1]
      if let styleMatch = matches("^\\s*(\\d+)m(\\d+)", in: style).first {
        methodIDs[m[0]] = "\(Int(styleMatch[0])!).\(Int(styleMatch[1])!)"
      }
    }

    var methods = [Method]()
    let classes = matches(
      "<packagedElement xmi:type=\"uml:Class\" xmi:id=\"([^\"]+)\" name=\"(Oca[A-Za-z0-9]+)\"[^>]*>(.*?)</packagedElement>",
      in: text,
      options: [.dotMatchesLineSeparators]
    )
    for cls in classes {
      guard let classID = matches("name=\"ClassID\".*?<defaultValue[^>]*value=\"([0-9.]+)\"", in: cls[2], options: [.dotMatchesLineSeparators]).first?[0]
      else { continue }
      for op in matches("<ownedOperation xmi:id=\"([^\"]+)\" name=\"([^\"]+)\"[^>]*>(.*?)</ownedOperation>", in: cls[2], options: [.dotMatchesLineSeparators]) {
        guard let methodID = methodIDs[op[0]] else { continue }
        let params = matches("<ownedParameter [^>]*name=\"([^\"]+)\" direction=\"(in|out|return)\"", in: op[2])
        methods.append(Method(
          classID: classID,
          className: cls[1],
          methodID: methodID,
          name: op[1],
          inputs: params.filter { $0[1] == "in" }.map { $0[0] },
          outputs: params.filter { $0[1] == "out" }.map { $0[0] }
        ))
      }
    }
    return methods
  }

  /// Judged by the same rule the protocol uses: `Ocp2Naming.matches` folds ASCII case
  /// and leading underscores, so only a genuinely different name counts.
  private static func namesMatch(_ sent: [String], _ expected: [String]) -> Bool {
    sent.count == expected.count && zip(sent, expected).allSatisfy(Ocp2Naming.matches)
  }

  func testDerivedAccessorNamesAgainstModel() async throws {
    guard let path = ProcessInfo.processInfo.environment["AES70_2_XMI"] else {
      throw XCTSkip("set AES70_2_XMI to the AES70-2 XMI file to run the naming oracle")
    }
    let model = try Self.loadModel(from: URL(fileURLWithPath: path))
    XCTAssertFalse(model.isEmpty, "no methods found in \(path)")
    let byClassAndMethod = Dictionary(
      model.map { ("\($0.classID)/\($0.methodID)", $0) },
      uniquingKeysWith: { first, _ in first }
    )

    var deviations = Set<String>()
    var checked = Set<String>()

    for (identification, type) in await OcaClassRegistry.shared.registeredClasses {
      let object = type.init(objectNumber: 0x0001_0000)
      let classID = identification.classID
      for (swiftName, keyPath) in object.allPropertyKeyPathsUncached {
        guard let property = object[keyPath: keyPath] as? any OcaPropertySubjectRepresentable,
              let propertyID = property.propertyIDs.first
        else { continue }
        _ = swiftName
        guard let wireName = property._ocp2WireName(object),
              let derived = property._ocp2ResponseNames(object)
        else { continue }
        let setName = property._ocp2SetName(object) ?? wireName

        // the accessor lives on the class at the property's definition level
        var definingClass = classID
        while definingClass.defLevel > propertyID.defLevel, let parent = definingClass.parent {
          definingClass = parent
        }
        func lookup(_ methodID: OcaMethodID?) -> Method? {
          guard let methodID else { return nil }
          return byClassAndMethod["\(definingClass)/\(methodID)"]
        }
        let getter = lookup(property.getMethodID)
        let setter = lookup(property.setMethodID)
        for (method, expected, sent) in [
          (getter, getter?.outputs, derived),
          (setter, setter?.inputs, [setName]),
        ] {
          guard let method, let expected, !expected.isEmpty else { continue }
          checked.insert("\(definingClass)/\(method.methodID)")
          if !Self.namesMatch(sent, expected) {
            deviations.insert("\(method.className) \(method.methodID) \(method.name): sends \(sent), model says \(expected)")
          }
        }
      }
    }

    print(
      "Ocp2 naming oracle: checked \(checked.count) accessors, \(deviations.count) deviations "
        + "(capitalisation alone is not a deviation)"
    )
    for deviation in deviations.sorted() {
      print("  \(deviation)")
    }
  }
}

#endif
