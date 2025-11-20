//
// Copyright (c) 2023-2025 PADL Software Pty Ltd
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

private struct ShowProgressIfWaitingViewModifier: ViewModifier {
  private let wrappedValue: any OcaPropertyRepresentable
  @State
  private var updateToggle = false

  init(wrappedValue: any OcaPropertyRepresentable) {
    self.wrappedValue = wrappedValue
  }

  func body(content: Content) -> some View {
    Group {
      if wrappedValue.hasValueOrError {
        content
      } else {
        ProgressView()
      }
    }
    .task {
      do {
        for try await _ in wrappedValue.async {
          await MainActor.run {
            updateToggle.toggle()
          }
        }
      } catch {}
    }
  }
}

public extension View {
  func showProgressIfWaiting(_ property: any OcaPropertyRepresentable) -> some View {
    modifier(ShowProgressIfWaitingViewModifier(wrappedValue: property))
  }
}
