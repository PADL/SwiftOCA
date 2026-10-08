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


#if canImport(FoundationXML)
import FoundationXML
#endif
import Foundation

/// An element of an XML document, with its attributes and the elements it contains.
final class XMINode {
  let name: String
  let attributes: [String: String]
  private(set) var children = [XMINode]()

  init(name: String, attributes: [String: String]) {
    self.name = name
    self.attributes = attributes
  }

  subscript(attribute: String) -> String? { attributes[attribute] }

  func children(named name: String) -> [XMINode] { children.filter { $0.name == name } }

  func child(named name: String) -> XMINode? { children.first { $0.name == name } }

  /// Every element below this one named `name`, at any depth.
  func descendants(named name: String) -> [XMINode] {
    children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(named: name) }
  }

  fileprivate func append(_ child: XMINode) { children.append(child) }

  /// The document's root element.
  static func parse(_ data: Data) throws -> XMINode {
    let builder = Builder()
    let parser = XMLParser(data: data)
    parser.delegate = builder
    guard parser.parse(), let root = builder.root else {
      throw OcaXMIError.malformed(parser.parserError.map { "\($0)" } ?? "no root element")
    }
    return root
  }

  private final class Builder: NSObject, XMLParserDelegate {
    var root: XMINode?
    private var stack = [XMINode]()

    func parser(
      _ parser: XMLParser,
      didStartElement elementName: String,
      namespaceURI: String?,
      qualifiedName: String?,
      attributes: [String: String] = [:]
    ) {
      let node = XMINode(name: elementName, attributes: attributes)
      stack.last?.append(node)
      if root == nil { root = node }
      stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
      stack.removeLast()
    }
  }
}

/// Why an XMI document could not be read.
public enum OcaXMIError: Error, Equatable {
  case malformed(String)
}
