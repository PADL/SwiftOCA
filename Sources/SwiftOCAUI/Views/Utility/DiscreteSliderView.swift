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

import Combine
import Sliders
import SwiftOCA
import SwiftUI

struct OcaDiscreteSliderView<Value: FixedWidthInteger & Codable>: View
    where Value.Stride: FixedWidthInteger
{
    @Binding
    var value: OcaBoundedPropertyValue<Value>
    @State
    var valuePublisher: CurrentValueSubject<Value, Never>
    var delay = 0.1

    var range: ClosedRange<Value> {
        value.minValue...value.maxValue
    }

    init(value: Binding<OcaBoundedPropertyValue<Value>>) {
        _value = value
        _valuePublisher =
            State(initialValue: CurrentValueSubject<Value, Never>(value.wrappedValue.value))
    }

    var body: some View {
        ValueSlider(
            value: Binding<Value>(get: { valuePublisher.value }, set: { valuePublisher.send($0) }),
            in: range
        )
        .onReceive(
            valuePublisher
                .debounce(for: .seconds(delay), scheduler: RunLoop.main)
        ) { newValue in
            value.value = newValue
        }
    }
}
