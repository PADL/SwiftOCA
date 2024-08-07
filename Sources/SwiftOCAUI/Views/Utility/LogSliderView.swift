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

struct OcaLogSliderView: View {
  static var step: OcaDB = 0.5

  @Binding
  var value: OcaBoundedPropertyValue<OcaDB>

  var linear: Binding<OcaFloat32> {
    Binding<OcaFloat32>(
      get: {
        OcaDBToFaderGain(dB: value.value, in: value.range)
      },
      set: { newValue in
        value.value = OcaFaderGainToDB(gain: newValue, in: value.range, step: Self.step)
      }
    )
  }

  var boundedLinear: Binding<OcaBoundedPropertyValue<OcaFloat32>> {
    Binding<OcaBoundedPropertyValue<OcaFloat32>>(
      get: {
        OcaBoundedPropertyValue<OcaFloat32>(value: linear.wrappedValue, in: 0.0...1.0)
      },
      set: { newValue in
        linear.wrappedValue = newValue.value
      }
    )
  }

  var body: some View {
    HStack {
      OcaScaledLegendView(value: value)
      OcaVariableSliderView<OcaFloat32>(value: boundedLinear)
        .valueSliderStyle(VerticalValueSliderStyle())
    }
    .padding(EdgeInsets(top: 25, leading: 0, bottom: 0, trailing: 0))
    .id(value.value)
  }
}

extension Binding where Value == OcaProperty<OcaBoundedPropertyValue<OcaFloat32>>.PropertyValue {
  var value: Binding<OcaBoundedPropertyValue<OcaFloat32>> {
    Binding<OcaBoundedPropertyValue<OcaFloat32>>(get: {
      if case let .success(value) = self.wrappedValue {
        value
      } else {
        OcaBoundedPropertyValue(value: 0.0, in: 0.0...0.0)
      }
    }, set: { newValue in
      self.wrappedValue = .success(newValue)
    })
  }
}
