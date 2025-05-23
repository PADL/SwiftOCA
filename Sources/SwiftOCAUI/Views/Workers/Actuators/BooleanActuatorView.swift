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

extension OcaBooleanActuator: OcaViewRepresentable {
  public var viewType: any OcaView.Type {
    OcaBooleanView.self
  }
}

private extension Binding where Value == OcaProperty<OcaBoolean>.PropertyValue {
  var value: Binding<Bool> {
    Binding<Bool>(get: {
      if case let .success(isOn) = self.wrappedValue {
        isOn
      } else {
        false
      }
    }, set: { isOn in
      self.wrappedValue = .success(isOn)
    })
  }
}

public struct OcaBooleanView: OcaView {
  @State
  var object: OcaBooleanActuator

  public init(_ object: OcaRoot) {
    _object = State(wrappedValue: object as! OcaBooleanActuator)
  }

  public var body: some View {
    Toggle(isOn: object.binding(for: object.$setting).value) {}
      .toggleStyle(SymbolToggleStyle(systemImage: "circle.fill", activeColor: .accentColor))
      .padding()
      .showProgressIfWaiting(object.setting)
  }
}
