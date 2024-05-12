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

import AsyncExtensions
import Combine
import SwiftOCA
import SwiftUI

public struct OcaRootBlockView: View {
  @Environment(\.lastError)
  var lastError
  @StateObject
  var connection: Ocp1Connection
  @State
  var oNoPath = NavigationPath()
  @State
  var object: OcaRoot? = nil

  public init(_ connection: Ocp1Connection) {
    _connection = StateObject(wrappedValue: connection)
  }

  public var body: some View {
    VStack {
      if let object {
        OcaBlockNavigationSplitView(object)
          .environment(\.navigationPath, $oNoPath)
          .environmentObject(connection)
      } else {
        ProgressView()
      }
    }.task {
      object = await connection.rootBlock
    }
  }
}
