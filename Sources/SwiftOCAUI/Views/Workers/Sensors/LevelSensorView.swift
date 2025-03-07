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

private struct OcaScaledGaugeView: View {
  private let scale: Float = 10.0
  private let gradient = Gradient(colors: [.green, .yellow, .orange, .red])

  var value: OcaBoundedPropertyValue<OcaDB>

  private var scaled: OcaFloat32 {
    OcaDBToFaderGain(dB: value.value, in: value.range)
  }

  private var boundedScaled: OcaBoundedPropertyValue<OcaFloat32> {
    OcaBoundedPropertyValue<OcaFloat32>(value: scaled / scale, in: 0.0...1.0)
  }

  var body: some View {
    Gauge(value: boundedScaled.value, in: boundedScaled.range) {
      EmptyView()
    }.tint(gradient)
      .labelStyle(.iconOnly)
      .rotationEffect(.degrees(-90))
      .scaleEffect(6)
      .scaledToFit()
  }
}

extension OcaLevelSensor: OcaViewRepresentable {
  public var viewType: any OcaView.Type {
    OcaLevelSensorView.self
  }

  var value: OcaBoundedPropertyValue<OcaDB> {
    if case let .success(readingValue) = reading {
      readingValue
    } else {
      // FIXME: constants
      OcaBoundedPropertyValue(value: -144.0, in: -144.0...0.0)
    }
  }
}

public struct OcaLevelSensorView: OcaView {
  @State
  var object: OcaLevelSensor

  public init(_ object: OcaRoot) {
    _object = State(wrappedValue: object as! OcaLevelSensor)
  }

  public var body: some View {
    OcaScaledGaugeView(value: object.value)
      .showProgressIfWaiting(object.reading)
  }
}
