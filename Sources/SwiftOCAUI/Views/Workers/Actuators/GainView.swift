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
import Sliders

fileprivate struct OcaLogSliderView: View {
    static var step: OcaDB = 0.5
    
    @Binding var value: OcaBoundedPropertyValue<OcaDB>
    
    var linear: Binding<OcaFloat32> {
        Binding<OcaFloat32>(get: {
            if value.maxValue == 0.0 {
                return 0.0
            }
            return OcaDBToGain(dB: value.value, minGain: value.minValue, maxGain: value.maxValue)
        },
                            set: { newValue in
            value.value = OcaGainToDB(gain: newValue,
                                      minGain: value.minValue,
                                      maxGain: value.maxValue,
                                      step: Self.step)
        })
    }
    
    var boundedLinear: Binding<OcaBoundedPropertyValue<OcaFloat32>> {
        return Binding<OcaBoundedPropertyValue<OcaFloat32>>(
            get: {
                OcaBoundedPropertyValue<OcaFloat32>(value: linear.wrappedValue / 10,
                                                    minValue: 0.0,
                                                    maxValue: 1.0)
            },
            set: { newValue in
                linear.wrappedValue = newValue.value * 10
            })
    }
    
    
    var body: some View {
        HStack {
            OcaLogLegendView(value: value)
            OcaVariableSliderView<OcaFloat32>(value: boundedLinear)
                .valueSliderStyle(VerticalValueSliderStyle())
        }
            .padding(EdgeInsets(top: 100, leading: 0, bottom: 100, trailing: 0))
    }
}

extension OcaGain: OcaViewRepresentable {
    public var viewType: any OcaView.Type {
        OcaGainView.self
    }
}

private extension Binding where Value == OcaProperty<OcaBoundedPropertyValue<OcaDB>>.State {
    var value: Binding<OcaBoundedPropertyValue<OcaDB>> {
        Binding<OcaBoundedPropertyValue<OcaFloat32>>(get: {
            if case let .success(gainValue) = self.wrappedValue {
                return gainValue
            } else {
                // FIXME: constants
                return OcaBoundedPropertyValue(value: 0.0, minValue: -1.0, maxValue: 1.0)
            }
       }, set: { newValue in
           self.wrappedValue = .success(newValue)
       })
    }
}

public struct OcaGainView: OcaView {
    @StateObject var object: OcaGain
    
    public init(_ object: OcaRoot) {
        self._object = StateObject(wrappedValue: object as! OcaGain)
    }
    
    public var body: some View {
        OcaLogSliderView(value: object.$gain.value)
            .showProgressIfWaiting(object.gain)
    }
}
