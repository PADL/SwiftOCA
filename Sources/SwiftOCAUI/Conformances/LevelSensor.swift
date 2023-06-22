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

struct OcaLogGaugeView: View {
    let gradient = Gradient(colors: [.green, .yellow, .orange, .red])

    @Binding var value: OcaBoundedPropertyValue<OcaDB>
    
    var linear: OcaFloat32 {
        if value.maxValue == 0.0 {
            return 0.0
        }
        return OcaDBToGain(dB: value.value, minGain: value.minValue, maxGain: value.maxValue)
    }
    
    var boundedLinear: OcaBoundedPropertyValue<OcaFloat32> {
        OcaBoundedPropertyValue<OcaFloat32>(value: linear / 10,
                                            minValue: 0.0,
                                            maxValue: 1.0)
    }
    
    var body: some View {
        Gauge(value: boundedLinear.value, in: boundedLinear.minValue...boundedLinear.maxValue) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        } minimumValueLabel: {
            Text(value.minValue.formatted()).rotationEffect(.degrees(-90))
        } maximumValueLabel: {
            Text(value.maxValue.formatted()).rotationEffect(.degrees(-90))
        }.tint(gradient)
            .labelStyle(.iconOnly)
            .rotationEffect(.degrees(90))
    }
}

extension OcaLevelSensor: OcaViewRepresentable {
    public var viewType: any OcaView.Type {
        OcaLevelSensorView.self
    }
    
    var readingValue: Binding<OcaBoundedPropertyValue<OcaDB>> {
        Binding<OcaBoundedPropertyValue<OcaDB>>(get: {
            if case let .success(readingValue) = self.reading {
                return readingValue
            } else {
                // FIXME: constants
                return OcaBoundedPropertyValue(value: 0.0, minValue: -144.0, maxValue: 20.0)
            }
        }, set: { newValue in
        })
    }
}

public struct OcaLevelSensorView: OcaView {
    @StateObject var object: OcaLevelSensor
    
    public init(_ object: OcaRoot) {
        self._object = StateObject(wrappedValue: object as! OcaLevelSensor)
    }
    
    public var body: some View {
        OcaLogGaugeView(value: object.readingValue)
            .showProgressIfWaiting(object.reading)
            .defaultPropertyModifiers(object, property: object.$reading)
    }
}
