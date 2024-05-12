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

import SwiftOCA
import SwiftUI

private struct RefreshableToInitialState: ViewModifier {
  let object: OcaRoot
  let property: (any OcaPropertyRepresentable)?

  init(_ object: OcaRoot, property: (any OcaPropertyRepresentable)? = nil) {
    self.object = object
    self.property = property
  }

  func body(content: Content) -> some View {
    content
      .refreshable {
        if let property {
          await property.refresh(object)
        } else {
          await object.refresh()
        }
      }
  }
}

public extension View {
  func refreshableToInitialState(
    _ object: OcaRoot,
    property: (any OcaPropertyRepresentable)? = nil
  ) -> some View {
    modifier(RefreshableToInitialState(object, property: property))
  }
}
