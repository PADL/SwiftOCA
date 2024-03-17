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

extension OcaMute: OcaViewRepresentable {
    public var viewType: any OcaView.Type {
        OcaMuteView.self
    }
}

private extension Binding where Value == OcaProperty<OcaMuteState>.PropertyValue {
    var value: Binding<Bool> {
        Binding<Bool>(get: {
            if case let .success(muteState) = self.wrappedValue {
                return muteState == .muted
            } else {
                return false
            }
        }, set: { isOn in
            self.wrappedValue = .success(isOn ? .muted : .unmuted)
        })
    }
}

public struct OcaMuteView: OcaView {
    @StateObject
    var object: OcaMute

    public init(_ object: OcaRoot) {
        _object = StateObject(wrappedValue: object as! OcaMute)
    }

    public var body: some View {
        Toggle(isOn: object.$state.binding.value) {}
            .toggleStyle(SymbolToggleStyle(
                systemImage: "speaker.slash.circle.fill",
                activeColor: .red
            ))
            .padding()
            .showProgressIfWaiting(object.state)
    }
}
