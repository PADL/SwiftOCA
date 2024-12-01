//
// Copyright (c) 2024 PADL Software Pty Ltd
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

@_spi(SwiftOCAPrivate)
import SwiftOCA
import SwiftUI

extension OcaRoot {
  func binding<Value: Codable & Sendable>(for property: OcaProperty<Value>)
    -> Binding<OcaProperty<Value>.PropertyValue>
  {
    Binding(
      get: {
        property.currentValue
      },
      set: { newValue in
        guard let newValue = try? newValue.asOptionalResult().get() else { return }
        Task { [weak self] in
          guard let self else { return }
          try await property._setValue(self, newValue)
        }
      }
    )
  }

  func binding<Value: Codable & Sendable>(for property: OcaBoundedProperty<Value>)
    -> Binding<OcaBoundedProperty<Value>.PropertyValue>
  {
    Binding(
      get: {
        property.currentValue
      },
      set: { newValue in
        guard let newValue = try? newValue.asOptionalResult().get() else { return }
        Task { [weak self] in
          guard let self else { return }
          try await property._setValue(self, newValue.value)
        }
      }
    )
  }

  func binding<Value: Codable & Sendable>(for property: OcaVectorProperty<Value>)
    -> Binding<OcaVectorProperty<Value>.PropertyValue>
  {
    Binding(
      get: {
        property.currentValue
      },
      set: { newValue in
        guard let newValue = try? newValue.asOptionalResult().get() else { return }
        Task { [weak self] in
          guard let self else { return }
          try await property._setValue(self, newValue)
        }
      }
    )
  }
}
