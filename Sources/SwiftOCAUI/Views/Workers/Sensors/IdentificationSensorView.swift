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

extension OcaIdentificationSensor: OcaViewRepresentable {
  public var viewType: any OcaView.Type {
    OcaIdentificationSensorView.self
  }
}

@Observable
private final class OcaIdentificationState: ObservableObject {
  var state: Bool = false

  func beginIdentifying() async {
    state = true
    try? await Task.sleep(for: .seconds(10))
    state = false
  }
}

public struct OcaIdentificationSensorView: OcaView {
  @State
  var object: OcaIdentificationSensor

  @State
  fileprivate var isIdentifying = OcaIdentificationState()

  public init(_ object: OcaRoot) {
    _object = State(wrappedValue: object as! OcaIdentificationSensor)
  }

  public var body: some View {
    Rectangle()
      .foregroundColor(isIdentifying.state ? Color.red : Color.black)
      .task {
        try? await object.onIdentify { _, _ in
          Task {
            await isIdentifying.beginIdentifying()
          }
        }
      }
  }
}
