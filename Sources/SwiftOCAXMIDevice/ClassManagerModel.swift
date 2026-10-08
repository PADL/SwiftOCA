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
  /// sets ModelURL to it. The document is written again only once the classes or
  /// datatypes the class manager describes have changed.
  func serveModel(on endpoint: OcaFlyingFoxDeviceEndpoint, path: String = "/aes70/model.xmi") async {
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
    modelURL = path
  }
}

/// The class model's document, kept for as long as what it describes does not change.
@OcaDevice
private final class ModelDocument: Sendable {
  private weak var classManager: SwiftOCADevice.OcaClassManager?
  private var described: (classes: [OcaClassDescriptor], datatypes: [OcaDatatypeDescriptor])?
  private var written = Data()

  init(_ classManager: SwiftOCADevice.OcaClassManager) {
    self.classManager = classManager
  }

  /// Nil once the class manager has gone.
  var document: Data? {
    guard let classManager else { return nil }
    let classes = classManager.controlClasses
    let datatypes = classManager.datatypes
    if described?.classes != classes || described?.datatypes != datatypes {
      written = Data(OcaXMIExport.document(classes: classes, datatypes: datatypes).utf8)
      described = (classes, datatypes)
    }
    return written
  }
}

#endif
