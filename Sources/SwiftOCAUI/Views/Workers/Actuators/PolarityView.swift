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

import SwiftUI
import SwiftOCA

extension OcaPolarity: OcaViewRepresentable {
    public var viewType: any OcaView.Type {
        OcaPolarityView.self
    }
    
    var isInverted: Binding<Bool> {
        Binding<Bool>(get: {
           if case let .success(state) = self.state {
               return state == .inverted
           } else {
               return false
           }
       }, set: { isInverted in
           self.state = .success(isInverted ? .inverted : .nonInverted)
       })
    }
}

public struct OcaPolarityView: OcaView {
    @StateObject var object: OcaPolarity

    public init(_ object: OcaRoot) {
        self._object = StateObject(wrappedValue: object as! OcaPolarity)
    }

    public var body: some View {
        Toggle(isOn: object.isInverted) {}
            .toggleStyle(SymbolToggleStyle(systemImage: "circle.slash", activeColor: .accentColor))
            .padding()
            .showProgressIfWaiting(object.state)
            .defaultPropertyModifiers(object, property: object.$state)
    }
}
