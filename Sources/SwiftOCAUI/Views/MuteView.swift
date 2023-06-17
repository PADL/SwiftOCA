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

extension OcaMute {
    var muteState: Binding<Bool> {
        Binding<Bool>(get: {
           if case let .success(muteState) = self.state {
               return muteState == .muted
           } else {
               return false
           }
       }, set: { isOn in
           self.state = .success(isOn ? .muted : .unmuted)
       })
    }
}

public struct OcaMuteView: OcaView {
    @StateObject var object: OcaMute

    public init(_ connection: AES70OCP1Connection, object: OcaObjectIdentification) {
        self._object = StateObject(wrappedValue: connection.resolve(object: object) as! OcaMute)
    }

    public var body: some View {
        Toggle(isOn: object.muteState) {}
            .toggleStyle(SymbolToggleStyle(systemImage: "speaker.slash.circle.fill", activeColor: .accentColor))
        .showProgressIfWaiting(object.state)
        .defaultPropertyModifiers(object, property: object.$state)
    }
}

// https://www.appcoda.com/swiftui-togglestyle/
struct SymbolToggleStyle: ToggleStyle {
    var systemImage: String = "speaker.slash.circle"
    var activeColor: Color = .green

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            RoundedRectangle(cornerRadius: 30)
                .fill(configuration.isOn ? activeColor : Color(.systemGray))
                .overlay {
                    Circle()
                        .fill(.white)
                        .padding(3)
                        .overlay {
                            Image(systemName: systemImage)
                                .foregroundColor(configuration.isOn ? activeColor : Color(.systemGray))
                        }
                        .offset(x: configuration.isOn ? 10 : -10)

                }
                .frame(width: 50, height: 32)
                .onTapGesture {
                    withAnimation(.spring()) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }
}
