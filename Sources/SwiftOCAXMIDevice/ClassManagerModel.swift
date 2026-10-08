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

#if NonEmbeddedBuild && canImport(FlyingFox)

import FlyingFox
import Foundation
@_spi(SwiftOCAPrivate) import SwiftOCA
@_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftOCAXMI

public extension SwiftOCADevice.OcaClassManager {
  /// Serves the device's class model as an XMI document at `path` on `endpoint`, and
  /// sets ModelURL to its URL at `host` once the endpoint's port is known. Serve it once
  /// per endpoint: a second route for the same path is never reached.
  func serveModel(
    on endpoint: OcaFlyingFoxDeviceEndpoint,
    path: String = "/aes70/model.xmi",
    host: String = OcaModelURL.defaultHost
  ) async {
    let model = ModelDocument(self)
    await endpoint.appendRoute(HTTPRoute("GET \(path)")) { _ in
      guard let document = await model.document else { return HTTPResponse(statusCode: .notFound) }
      // XMI is XML; there is no registered media type of its own
      return HTTPResponse(
        statusCode: .ok,
        headers: [.contentType: "application/xml; charset=utf-8"],
        body: document
      )
    }
    if let port = await endpoint.listeningPort {
      modelURL = OcaModelURL.url(host: host, port: port, path: path)
      return
    }
    // bound to port 0, so the port is known only once the endpoint is listening
    Task { [weak self, weak endpoint] in
      while let endpoint, self != nil, !Task.isCancelled {
        guard (try? await endpoint.waitUntilListening()) != nil, let port = await endpoint.listeningPort else { continue }
        self?.modelURL = OcaModelURL.url(host: host, port: port, path: path)
        return
      }
    }
  }
}

/// How ModelURL names the model: over HTTP, as OcaFlyingFoxDeviceEndpoint serves it.
public enum OcaModelURL {
  /// The system's host name, with `.local` added where it has no domain: devices
  /// advertise themselves with mDNS, so that name resolves on the link the device is on.
  public static var defaultHost: String {
    let name = ProcessInfo.processInfo.hostName
    return name.contains(".") ? name : name + ".local"
  }

  /// The URL of `path` at `host` and `port`; an IPv6 address is bracketed, as RFC 3986
  /// writes it.
  public static func url(host: String, port: UInt16, path: String) -> String {
    let host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    return "http://\(host):\(port)\(path.hasPrefix("/") ? path : "/" + path)"
  }
}

/// The class model's document, written again only once what it describes has changed.
@OcaDevice
private final class ModelDocument {
  private weak var classManager: SwiftOCADevice.OcaClassManager?
  private var classes = [OcaClassDescriptor]()
  private var datatypes = [OcaDatatypeDescriptor]()
  private var written: Data?

  init(_ classManager: SwiftOCADevice.OcaClassManager) {
    self.classManager = classManager
  }

  /// Nil once the class manager has gone.
  var document: Data? {
    guard let classManager else { return nil }
    if written == nil || classes != classManager.controlClasses || datatypes != classManager.datatypes {
      classes = classManager.controlClasses
      datatypes = classManager.datatypes
      written = Data(OcaXMIExport.document(classes: classes, datatypes: datatypes).utf8)
    }
    return written
  }
}

#endif
