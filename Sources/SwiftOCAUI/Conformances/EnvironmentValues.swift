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

private struct NavigationPathKey: EnvironmentKey {
  static let defaultValue = Binding<NavigationPath>(get: { NavigationPath() }, set: { _ in })
}

extension EnvironmentValues {
  var navigationPath: Binding<NavigationPath> {
    get { self[NavigationPathKey.self] }
    set { self[NavigationPathKey.self] = newValue }
  }
}

private struct LastErrorKey: EnvironmentKey {
  static let defaultValue = Binding<Error?>(get: { nil }, set: { _ in })
}

extension EnvironmentValues {
  var lastError: Binding<Error?> {
    get { self[LastErrorKey.self] }
    set { self[LastErrorKey.self] = newValue }
  }
}
