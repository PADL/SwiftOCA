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

import Sliders
import SwiftOCA
import SwiftUI

extension OcaPanBalance: OcaViewRepresentable {
    public var viewType: any OcaView.Type {
        OcaPanBalanceView.self
    }
}

private extension Binding where Value == OcaProperty<OcaBoundedPropertyValue<OcaFloat32>>.State {
    var value: Binding<OcaBoundedPropertyValue<OcaFloat32>> {
        Binding<OcaBoundedPropertyValue<OcaFloat32>>(get: {
            if case let .success(positionValue) = self.wrappedValue {
                return positionValue
            } else {
                // FIXME: constants
                return OcaBoundedPropertyValue(value: 0.0, minValue: -1.0, maxValue: 1.0)
            }
        }, set: { newValue in
            self.wrappedValue = .success(newValue)
        })
    }
}

public struct OcaPanBalanceView: OcaView {
    @StateObject
    var object: OcaPanBalance

    public init(_ object: OcaRoot) {
        _object = StateObject(wrappedValue: object as! OcaPanBalance)
    }

    public var body: some View {
        OcaVariableSliderView(value: object.$position.value)
            .valueSliderStyle(HorizontalValueSliderStyle())
            .showProgressIfWaiting(object.position)
    }
}
