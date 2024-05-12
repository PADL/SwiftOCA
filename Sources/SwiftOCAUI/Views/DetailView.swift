//
// Copyright (c) 2023 PADL Software Pty Ltd
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

import Combine
import SwiftOCA
import SwiftUI

public protocol OcaViewRepresentable: OcaRoot {
  var viewType: any OcaView.Type { get }
}

extension Array where Element: OcaRoot {
  var allMembersAreViewRepresentable: Bool {
    allSatisfy { $0 is OcaViewRepresentable }
  }
}

public struct OcaDetailView: OcaView {
  let connection: Ocp1Connection
  let objectIdentification: OcaObjectIdentification

  @Environment(\.lastError)
  var lastError
  @State
  var object: OcaRoot? = nil

  public init(
    _ connection: Ocp1Connection,
    objectIdentification: OcaObjectIdentification
  ) {
    self.connection = connection
    self.objectIdentification = objectIdentification
  }

  public init(_ object: SwiftOCA.OcaRoot) {
    self.init(object.connectionDelegate!, objectIdentification: object.objectIdentification)
  }

  public var body: some View {
    Group {
      if let object {
        let metatype = type(of: object)
        Group {
          if metatype == OcaBlock.self {
            OcaBlockNavigationStackView(object)
          } else if metatype == OcaMatrix.self {
            OcaMatrixNavigationSplitView(object)
          } else if let object = object as? OcaViewRepresentable {
            // use type erasure as last resort
            AnyView(erasing: object.viewType.init(object))
          } else {
            OcaPropertyTableView(object)
          }
        }.refreshableToInitialState(object)
      } else {
        ProgressView()
      }
    }
    .task {
      object = try? await connection.resolve(object: objectIdentification)
    }
  }
}
