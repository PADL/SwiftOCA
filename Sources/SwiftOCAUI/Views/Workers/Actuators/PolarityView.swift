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

public struct OcaPolarityView: OcaView {
  @State
  var object: OcaPolarity

  public init(_ object: OcaRoot) {
    _object = State(wrappedValue: object as! OcaPolarity)
  }

  public var body: some View {
    OcaWritablePropertyView(object, object.$state) { (value: Binding<OcaPolarityState>) in
      let boolBinding = Binding<Bool>(
        get: { value.wrappedValue == .inverted },
        set: { value.wrappedValue = $0 ? .inverted : .nonInverted }
      )
      Toggle(isOn: boolBinding) {}
        .toggleStyle(SymbolToggleStyle(systemImage: "circle.slash", activeColor: .accentColor))
        .padding()
    }
  }
}
