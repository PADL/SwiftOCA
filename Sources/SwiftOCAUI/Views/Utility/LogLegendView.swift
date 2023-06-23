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

struct OcaLogLegendView: View {
    var value: OcaBoundedPropertyValue<OcaDB>

    private func y(_ value: Int) -> CGFloat {
        let dB = Float(value * 10)
        return 1.0 - CGFloat(OcaDBToGain(dB: dB, minGain: self.value.minValue, maxGain: self.value.maxValue)) / 10
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Int(value.minValue / 10)...Int(value.maxValue / 10), id: \.self) { value in
                    Text(String(value * 10))
                        .font(.caption2)
                        .frame(maxWidth: 20, alignment: .trailing)
                        .position(x: geo.size.width * 0.1, y: geo.size.height * y(value))
                }
            }
        }
    }
}
