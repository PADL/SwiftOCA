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

/// The Swift spelling of a model name: `SetPortName` → `setPortName`, `ONo` → `oNo`.
enum ModelNaming {
  /// Acronyms the model (and the proprietary descriptors) start a name with, and their
  /// Swift spelling; applied to the leading run of capitals only, so `ConfigureEndpointFromSDP`
  /// keeps its tail. The model's own leading runs are GUID, ID and ONo (`IDAdvertised`,
  /// `ONoPath`, `ONos`); the descriptors add SDP (`SDPString`); the rest are listed for
  /// names the adaptations may yet use. `NSegments` is not an acronym and becomes `nSegments`.
  static let acronyms: [(model: String, swift: String)] = [
    ("AES67", "aes67"), ("GUID", "guid"), ("ID", "id"), ("IP", "ip"), ("MAC", "mac"),
    ("NTP", "ntp"), ("ONo", "oNo"), ("PTP", "ptp"), ("SDP", "sdp"), ("SIP", "sip"),
    ("URL", "url"), ("UUID", "uuid"),
  ]

  static func lowerCamel(_ name: String) -> String {
    for (model, swift) in acronyms.sorted(by: { $0.model.count > $1.model.count })
      where name.hasPrefix(model)
    {
      let rest = name.dropFirst(model.count)
      if rest.first.map({ $0.isUppercase || $0.isNumber }) ?? true {
        return swift + rest
      }
    }
    guard let first = name.first else { return name }
    return first.lowercased() + name.dropFirst()
  }
}

/// Every method with a descriptor is spelled as the model names it, on both sides: the
/// method name is `lowerCamel` of the model's, each argument label is `lowerCamel` of the
/// model's parameter name in the model's order and is also the internal name, and the
/// result is the model's scalar or record, never a tuple. The device's implementing
/// method differs only by a trailing `from controller`.
final class ModelMethodNameTests: XCTestCase {
  private static let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources")

  private struct Signature {
    let owner: String
    let name: String
    let parameters: [(label: String, internalName: String, type: String)]
    let returnType: String?
    let location: String

    var spelling: String {
      "\(name)(\(parameters.map { "\($0.label):" }.joined()))"
    }
  }

  private static func expectedSpelling(_ descriptor: OcaAnyMethodDescriptor) -> (
    name: String, labels: [String]
  ) {
    (
      ModelNaming.lowerCamel(descriptor.name),
      descriptor.parameters.map { ModelNaming.lowerCamel($0.name) }
    )
  }

  /// The problems with `signature` standing for `descriptor`; `controller` for the device.
  private static func problems(
    _ signature: Signature,
    for descriptor: OcaAnyMethodDescriptor,
    controller: Bool
  ) -> [String] {
    let expected = expectedSpelling(descriptor)
    var problems = [String]()
    var parameters = signature.parameters
    if controller {
      if let last = parameters.last, last.label == "from", last.internalName == "controller",
         last.type.contains("OcaController")
      {
        parameters.removeLast()
      } else {
        problems.append("no trailing `from controller: any OcaController`")
      }
    }
    if signature.name != expected.name {
      problems.append("name \(signature.name), model says \(expected.name)")
    }
    if parameters.map(\.label) != expected.labels {
      problems.append(
        "labels (\(parameters.map(\.label).joined(separator: ", "))), model says (\(expected.labels.joined(separator: ", ")))"
      )
    }
    for parameter in parameters where parameter.label != parameter.internalName {
      problems.append("`\(parameter.label) \(parameter.internalName)`: internal name must be the label")
    }
    if let returnType = signature.returnType {
      if descriptor.results.isEmpty, returnType != "Void", returnType != "()" {
        problems.append("returns \(returnType), model has no result")
      } else if returnType.hasPrefix("(") {
        problems.append("returns the tuple \(returnType), model has the record")
      }
    } else if !descriptor.results.isEmpty {
      problems.append("returns nothing, model has \(descriptor.results.map(\.name).joined(separator: ", "))")
    }
    return problems
  }

  /// Every client descriptor has a method of the model's spelling in its class.
  func testClientMethodsAreSpelledAsTheModel() throws {
    let signatures = try Self.signatures(under: Self.sources.appendingPathComponent("SwiftOCA"))
    var failures = [String]()
    var checked = 0
    for (type, descriptors) in ClientMethodDescriptors.all {
      let owner = Self.className(type)
      for (_, descriptor) in descriptors {
        checked += 1
        let expected = Self.expectedSpelling(descriptor)
        let candidates = signatures.filter { $0.owner == owner && $0.name == expected.name }
        if candidates.isEmpty {
          failures.append("\(owner).\(descriptor.name): no method \(expected.name)")
          continue
        }
        if candidates.contains(where: { Self.problems($0, for: descriptor, controller: false).isEmpty }) {
          continue
        }
        for candidate in candidates {
          let problems = Self.problems(candidate, for: descriptor, controller: false)
          failures.append("\(owner).\(descriptor.name) \(candidate.location) \(candidate.spelling): \(problems.joined(separator: "; "))")
        }
      }
    }
    print("model naming: \(checked) client descriptors, \(failures.count) methods not spelled as the model")
    XCTAssertEqual(failures.sorted(), [], "\n" + failures.sorted().joined(separator: "\n"))
  }

  /// Every `@OcaDeviceMethod(descriptor)` site implements the method under the model's
  /// spelling plus `from controller`.
  func testDeviceMethodsAreSpelledAsTheModel() throws {
    let device = Self.sources.appendingPathComponent("SwiftOCADevice")
    let signatures = try Self.signatures(under: device)
    let sites = try Self.deviceMethodSites(under: device)
    XCTAssertFalse(Self.swiftFiles(under: device).isEmpty, "no sources under \(device.path)")
    let descriptors = Dictionary(uniqueKeysWithValues: ClientMethodDescriptors.all.map { type, entries in
      (Self.className(type), Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.descriptor) }))
    })
    var failures = [String]()
    var checked = 0
    for site in sites {
      // the descriptor's class is named at the site, or is the implementing class itself
      guard let descriptor = descriptors[site.descriptorOwner]?[site.descriptorName]
        ?? descriptors[site.owner]?[site.descriptorName]
      else {
        failures.append("\(site.location): no client descriptor \(site.descriptorOwner).\(site.descriptorName)")
        continue
      }
      guard let signature = signatures.first(where: { $0.location == site.location }) else {
        failures.append("\(site.location): no method follows the annotation")
        continue
      }
      checked += 1
      let problems = Self.problems(signature, for: descriptor, controller: true)
      if !problems.isEmpty {
        failures.append("\(site.owner).\(descriptor.name) \(site.location) \(signature.spelling): \(problems.joined(separator: "; "))")
      }
    }
    print("model naming: \(checked) device method sites, \(failures.count) not spelled as the model")
    XCTAssertEqual(failures.sorted(), [], "\n" + failures.sorted().joined(separator: "\n"))
  }

  /// `lowerCamel` inverts `Ocp2Naming.wireName` for every name in the model, up to case
  /// for the 2023 model's lower-case spellings (`minGain`) and the names starting with an
  /// acronym (`ID` → `id` → `Id`), which the descriptors name explicitly. Point
  /// `AES70_2_XMI` at the model to run it.
  func testLowerCamelInvertsTheWireName() throws {
    guard let path = ProcessInfo.processInfo.environment["AES70_2_XMI"] else {
      throw XCTSkip("set AES70_2_XMI to the AES70-2 XMI to run the naming oracle")
    }
    let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .windowsCP1252)
    let regex = try NSRegularExpression(
      pattern: #"<(?:ownedOperation|ownedParameter) [^>]*name="([^"]+)""#
    )
    var names = Set<String>()
    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
      names.insert(String(text[Range(match.range(at: 1), in: text)!]))
    }
    XCTAssertGreaterThan(names.count, 500)
    let inverted = names.map { ($0, Ocp2Naming.wireName(ModelNaming.lowerCamel($0))) }
    XCTAssertEqual(inverted.filter { !Ocp2Naming.matches($0.0, $0.1) }.map(\.0).sorted(), [])
    let exceptions = inverted.filter { $0.0 != $0.1 && $0.0.first!.isUppercase }.map(\.0)
    XCTAssertEqual(exceptions.sorted(), ["GUID", "ID", "IDAdvertised"])
    let lowerCase = inverted.filter { $0.0 != $0.1 && !$0.0.first!.isUppercase }.count
    print("model naming: \(names.count) model names, \(exceptions.count) acronym names and \(lowerCase) lower-case spellings inverted up to case")
  }

  private static func className(_ type: Any.Type) -> String {
    String(String(describing: type).prefix { $0 != "<" })
  }

  private struct Site {
    let owner: String
    let descriptorOwner: String
    let descriptorName: String
    let location: String
  }

  private static let typeDecl = try! NSRegularExpression(
    pattern: #"^\s*(?:@\w+\s+)*(?:open |public |final |private |fileprivate |package )*(?:class|extension|struct|enum|actor) ([\w.]+)"#
  )
  private static let funcDecl = try! NSRegularExpression(
    pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:open |public |package |internal |private |fileprivate |final |override |nonisolated |static |class )*func (\w+)\s*\("#
  )
  private static let site = try! NSRegularExpression(
    pattern: #"^\s*@OcaDeviceMethod\((?:SwiftOCA\.)?(\w+)\.Methods\.(\w+)"#
  )

  private static func swiftFiles(under directory: URL) -> [URL] {
    FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" }
      .sorted { $0.path < $1.path }
  }

  /// Walks `lines` keeping the innermost enclosing type; `body` sees each line with it.
  private static func walk(_ lines: [String], _ body: (Int, String, String?) -> Void) {
    var stack = [(depth: Int, name: String)]()
    var depth = 0
    var pending: String?
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
      body(index, line, stack.last?.name)
      depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
      while let last = stack.last, depth <= last.depth {
        stack.removeLast()
      }
    }
  }

  private static func deviceMethodSites(under directory: URL) throws -> [Site] {
    var sites = [Site]()
    for file in swiftFiles(under: directory) {
      let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
      walk(lines) { index, line, owner in
        // a wrapped attribute names the descriptor on its next line
        let line = line.hasSuffix("@OcaDeviceMethod(") && index + 1 < lines.count
          ? line + lines[index + 1].trimmingCharacters(in: .whitespaces)
          : line
        guard let owner,
              let match = site.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return }
        // the method follows, after any further attributes
        var next = index + 1
        while next < lines.count,
              funcDecl.firstMatch(in: lines[next], range: NSRange(lines[next].startIndex..., in: lines[next])) == nil
        {
          next += 1
        }
        guard next < lines.count else { return }
        sites.append(Site(
          owner: owner,
          descriptorOwner: String(line[Range(match.range(at: 1), in: line)!]),
          descriptorName: String(line[Range(match.range(at: 2), in: line)!]),
          location: "\(file.lastPathComponent):\(next + 1)"
        ))
      }
    }
    return sites
  }

  /// Every method declaration under `directory`, with its enclosing type.
  private static func signatures(under directory: URL) throws -> [Signature] {
    var signatures = [Signature]()
    for file in swiftFiles(under: directory) {
      let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
      walk(lines) { index, line, owner in
        guard let owner,
              let match = funcDecl.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return }
        let name = String(line[Range(match.range(at: 1), in: line)!])
        // gather the text from the opening parenthesis to the body's brace, or to the end
        // of the signature of a method whose body a macro writes
        var text = String(line[line.index(line.startIndex, offsetBy: match.range.upperBound)...])
        var next = index + 1
        while !text.contains("{"), next < lines.count, !Self.endsSignature(lines[next]) {
          text += " " + lines[next]
          next += 1
        }
        guard let (parameters, rest) = splitParameters(text) else { return }
        let returnType = rest.range(of: "->").map { arrow in
          rest[arrow.upperBound...].prefix { $0 != "{" }.trimmingCharacters(in: .whitespaces)
        }
        signatures.append(Signature(
          owner: owner,
          name: name,
          parameters: parameters.map(parseParameter),
          returnType: returnType,
          location: "\(file.lastPathComponent):\(index + 1)"
        ))
      }
    }
    return signatures
  }

  /// Whether `line` follows a signature without a body: a blank line, a comment, an
  /// attribute, or the end of the type.
  private static func endsSignature(_ line: String) -> Bool {
    let line = line.trimmingCharacters(in: .whitespaces)
    return line.isEmpty || line.hasPrefix("//") || line.hasPrefix("@") || line.hasPrefix("}")
  }

  /// The parameters of `text`, which starts just inside the opening parenthesis, and the
  /// text after the closing one.
  private static func splitParameters(_ text: String) -> ([String], String)? {
    var depth = 0
    var current = ""
    var parameters = [String]()
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      switch character {
      case "(", "[", "<":
        depth += 1
      case ")", "]":
        if depth == 0 {
          if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parameters.append(current)
          }
          return (parameters, String(text[text.index(after: index)...]))
        }
        depth -= 1
      case ">":
        if text[text.index(before: index)] != "-" { depth -= 1 }
      case "," where depth == 0:
        parameters.append(current)
        current = ""
        index = text.index(after: index)
        continue
      default:
        break
      }
      current.append(character)
      index = text.index(after: index)
    }
    return nil
  }

  private static func parseParameter(_ text: String) -> (label: String, internalName: String, type: String) {
    let declaration = text.split(separator: "=", maxSplits: 1)[0]
    guard let colon = declaration.firstIndex(of: ":") else { return ("", "", "") }
    let names = declaration[..<colon].split(separator: " ").filter { !$0.hasPrefix("@") && $0 != "inout" }
    let type = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    let label = names.first.map(String.init) ?? ""
    return (label, names.count > 1 ? String(names[1]) : label, type)
  }
}
#endif
